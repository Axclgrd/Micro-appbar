import Darwin
import Foundation

// Les sondes système : processeur, mémoire, disque, réseau.
//
// Tout passe par les API du noyau — `host_statistics`, `sysctl`, `getifaddrs`.
// Aucun sous-processus : `top` et `vm_stat` donnent exactement les mêmes
// chiffres, mais coûtent un fork à chaque relevé et obligent à analyser du
// texte localisé qui change d'une version de macOS à l'autre.
//
// Deux de ces mesures sont des **débits** : la charge processeur et le réseau
// ne se lisent pas, ils se déduisent de deux relevés. D'où les compteurs
// gardés d'un tour sur l'autre, et la première mesure qui ne vaut rien.

/// Compteurs cumulés du processeur, en « ticks » depuis le démarrage.
struct CPUTicks {
    let user: UInt64
    let system: UInt64
    let idle: UInt64

    var total: UInt64 { user + system + idle }
}

enum Sondes {

    // MARK: Processeur

    static let cores = ProcessInfo.processInfo.processorCount

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // `nice` compte à part dans la structure, mais c'est du temps
        // utilisateur : l'oublier ferait disparaître la charge des tâches
        // lancées avec une priorité abaissée — une compilation, typiquement.
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.3),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2)
        )
    }

    static func cpuLoad(from previous: CPUTicks, to current: CPUTicks) -> CPULoad {
        let span = current.total &- previous.total
        guard span > 0 else { return CPULoad(user: 0, system: 0, cores: cores) }
        return CPULoad(
            user: Double(current.user &- previous.user) / Double(span),
            system: Double(current.system &- previous.system) / Double(span),
            cores: cores
        )
    }

    // MARK: Mémoire

    static func memory() -> MemoryUsage {
        // `sysconf` plutôt que `vm_kernel_page_size` : la variable globale de
        // Mach n'est pas sûre vis-à-vis de la concurrence, et la valeur est la
        // même — 16 Ko sur Apple Silicon, 4 Ko sur Intel.
        let page = UInt64(sysconf(_SC_PAGESIZE))
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return MemoryUsage(total: total, app: 0, wired: 0, compressed: 0,
                               cached: 0, swapUsed: swap(), pression: pression())
        }

        // Les pages « internes » sont celles des applications ; les
        // « externes » sont des fichiers que macOS garde sous la main et rend
        // dès qu'on les lui demande. Compter ces dernières comme occupées
        // ferait croire à une machine pleine en permanence.
        let purgeable = UInt64(stats.purgeable_count)
        let internalPages = UInt64(stats.internal_page_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * page

        return MemoryUsage(
            total: total,
            app: app,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cached: (UInt64(stats.external_page_count) + purgeable) * page,
            swapUsed: swap(),
            pression: pression()
        )
    }

    private static func swap() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private static func pression() -> Pression {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        else { return .normale }
        return Pression(rawValue: Int(level)) ?? .normale
    }

    // MARK: Disque

    /// Le volume de démarrage, le seul dont le remplissage ralentisse le Mac.
    static func disk() -> DiskUsage? {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }

        // « Important usage » est la place que le Finder annonce : elle inclut
        // ce que macOS sait purger (instantanés locaux, corbeille). C'est la
        // seule valeur qui corresponde à ce qu'on peut vraiment écrire.
        let free = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) } ?? 0
        return DiskUsage(name: values.volumeName ?? "Disque", free: free, total: UInt64(total))
    }

    // MARK: Réseau

    /// Octets cumulés par interface. Les compteurs du noyau sont sur 32 bits :
    /// ils débordent tous les 4 Go, d'où la soustraction par interface, en
    /// arithmétique circulaire, plutôt que sur un total.
    static func interfaceBytes() -> [String: (down: UInt32, up: UInt32)] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var table: [String: (down: UInt32, up: UInt32)] = [:]
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard pointer.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: pointer.pointee.ifa_name)
            // La boucle locale double chaque octet échangé entre deux process
            // de la machine ; les ponts `utun`, `bridge` et `awdl` recomptent
            // ce qui passe déjà par le Wi-Fi.
            guard !name.hasPrefix("lo"), !name.hasPrefix("utun"),
                  !name.hasPrefix("bridge"), !name.hasPrefix("awdl"),
                  !name.hasPrefix("llw"), !name.hasPrefix("gif"), !name.hasPrefix("stf")
            else { continue }
            guard let data = pointer.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }
            table[name] = (data.pointee.ifi_ibytes, data.pointee.ifi_obytes)
        }
        return table
    }

    static func rate(from previous: [String: (down: UInt32, up: UInt32)],
                     to current: [String: (down: UInt32, up: UInt32)],
                     seconds: Double) -> NetworkRate {
        guard seconds > 0 else { return .zero }
        var down: UInt64 = 0, up: UInt64 = 0
        for (name, now) in current {
            guard let before = previous[name] else { continue }
            down += UInt64(now.down &- before.down)
            up += UInt64(now.up &- before.up)
        }
        return NetworkRate(down: Double(down) / seconds, up: Double(up) / seconds)
    }
}
