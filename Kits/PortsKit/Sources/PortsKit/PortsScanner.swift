import Darwin
import Foundation

// Qui écoute sur quel port — sans `lsof`, en API système.
//
// `lsof` aurait marché, mais il liste chaque socket deux fois (IPv4 puis IPv6),
// tronque les noms de process à neuf caractères — `com.docke` pour
// `com.docker.backend` — et coûte un sous-processus à chaque sondage. `libproc`
// donne la même chose en direct, dédoublonné et complet.
//
// Portée : les process de l'utilisateur courant. Ceux des autres comptes et de
// root sont ignorés faute de droits — c'est voulu, un outil qui demande root
// pour lister des ports serait disproportionné.

struct Listener: Identifiable, Sendable, Equatable {
    var id: String { "\(pid)-\(port)" }

    let port: UInt16
    let pid: Int32
    /// Le nom du binaire : `node`, `com.docker.backend`, `ControlCenter`.
    let process: String
    /// Le dossier de travail — c'est lui qui dit *quel projet* tourne.
    let directory: String
    let started: Date

    /// Ce que l'outil a compris de ce port, et ce que l'arrêter coûterait.
    let verdict: Verdict
    let note: String

    /// Le nom du projet, quand le dossier de travail en désigne un.
    var project: String? {
        guard directory.hasPrefix(NSHomeDirectory()), directory != NSHomeDirectory() else { return nil }
        let name = (directory as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    var age: TimeInterval { Date().timeIntervalSince(started) }
}

/// Trois verdicts, comme dans Purge : c'est le verdict qui décide de ce qu'on
/// propose, pas l'envie de tout pouvoir tuer.
enum Verdict: Sendable {
    /// Un serveur de développement. C'est ce qu'on vient arrêter.
    case yours
    /// Une autre application. L'arrêter marche, mais fait plus que libérer le port.
    case care
    /// Un service du système. On explique, on ne tue pas.
    case system

    var label: String {
        switch self {
        case .yours:  "à toi"
        case .care:   "attention"
        case .system: "système"
        }
    }
}

enum PortsScanner {

    /// Les binaires qui, chez un développeur, sont presque toujours un serveur
    /// lancé à la main — donc ce qu'on cherche à récupérer.
    private static let devProcesses: Set<String> = [
        "node", "bun", "deno", "python3", "python", "ruby", "php", "java",
        "next-server", "vite", "esbuild", "webpack", "rails", "puma", "gunicorn",
        "uvicorn", "flask", "cargo", "air", "dotnet", "http-server", "serve",
    ]

    /// Ce que le système tient et qu'il ne faut pas tuer — avec, quand elle
    /// existe, la façon correcte de libérer le port.
    private static func systemNote(process: String, port: UInt16) -> String? {
        switch process {
        case "ControlCenter" where port == 5000 || port == 7000:
            "Récepteur AirPlay de macOS. C'est lui qui rend le port 5000 « déjà utilisé ». Il se coupe dans Réglages système › Général › AirDrop et Handoff › Récepteur AirPlay."
        case "ControlCenter":
            "Centre de contrôle de macOS."
        case "rapportd":
            "Service de continuité d'Apple — Handoff, AirDrop, Relais."
        case "sharingd":
            "Partage de fichiers et d'écran de macOS."
        case "AirPlayXPCHelper", "remoted", "identityservicesd":
            "Service interne de macOS."
        default:
            nil
        }
    }

    private static func careNote(process: String) -> String? {
        switch process {
        case let name where name.hasPrefix("com.docker"):
            "Ce port est publié par Docker, pas par le programme qui écoute dedans. Arrêter ce process coupe Docker en entier — conteneurs compris. Préfère `docker stop` sur le bon conteneur."
        case "Adobe Desktop Service", "Creative Cloud", "AdobeIPCBroker":
            "Service d'arrière-plan d'Adobe Creative Cloud."
        case "Code Helper", "Code", "Electron":
            "Processus d'un éditeur ouvert."
        default:
            nil
        }
    }

    /// Les ports dont le numéro dit déjà à quoi on a affaire.
    private static func wellKnown(_ port: UInt16) -> String? {
        switch port {
        case 3000, 3001: "Port par défaut de Next.js, Rails et Express."
        case 5173, 5174: "Port par défaut de Vite."
        case 4200: "Port par défaut d'Angular."
        case 8080, 8000: "Port de développement courant."
        case 5432, 5433, 5434: "PostgreSQL."
        case 3306: "MySQL ou MariaDB."
        case 6379: "Redis."
        case 27017: "MongoDB."
        case 5050: "pgAdmin."
        default: nil
        }
    }

    // MARK: Lecture

    nonisolated static func scan() -> [Listener] {
        var found: [Listener] = []
        var seen: Set<String> = []

        for pid in pids() {
            let ports = listeningPorts(of: pid)
            guard !ports.isEmpty else { continue }
            let process = name(of: pid)
            let directory = workingDirectory(of: pid)
            let started = startDate(of: pid)

            for port in ports {
                let key = "\(pid)-\(port)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                let verdict: Verdict
                var note: String

                if let system = systemNote(process: process, port: port) {
                    verdict = .system
                    note = system
                } else if let care = careNote(process: process) {
                    verdict = .care
                    note = care
                } else if devProcesses.contains(process) {
                    verdict = .yours
                    note = "Serveur de développement."
                } else {
                    verdict = .care
                    note = "Application ouverte."
                }

                if let known = wellKnown(port), verdict != .system {
                    note += " " + known
                }

                found.append(Listener(port: port, pid: pid, process: process,
                                      directory: directory, started: started,
                                      verdict: verdict, note: note))
            }
        }
        return found.sorted { $0.port < $1.port }
    }

    private nonisolated static func pids() -> [Int32] {
        let size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return [] }
        var buffer = [Int32](repeating: 0, count: Int(size) / MemoryLayout<Int32>.size)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, size)
        guard written > 0 else { return [] }
        return Array(buffer.prefix(Int(written) / MemoryLayout<Int32>.size)).filter { $0 > 0 }
    }

    private nonisolated static func listeningPorts(of pid: Int32) -> [UInt16] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(),
                                        count: Int(size) / MemoryLayout<proc_fdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, size)
        guard written > 0 else { return [] }

        var ports: Set<UInt16> = []
        for descriptor in descriptors.prefix(Int(written) / MemoryLayout<proc_fdinfo>.size)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let read = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO,
                                      &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard read == Int32(MemoryLayout<socket_fdinfo>.size),
                  info.psi.soi_kind == SOCKINFO_TCP,
                  info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN
            else { continue }
            // Le port est en ordre réseau dans la structure du noyau.
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport))
            if port > 0 { ports.insert(port) }
        }
        return Array(ports)
    }

    /// `String(cString:)` sur un tableau est déprécié : le tampon est coupé au
    /// premier octet nul avant d'être décodé.
    private nonisolated static func text(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private nonisolated static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "inconnu" }
        return (text(buffer) as NSString).lastPathComponent
    }

    private nonisolated static func workingDirectory(of pid: Int32) -> String {
        var info = proc_vnodepathinfo()
        let read = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info,
                                Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard read > 0 else { return "" }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else { return "" }
            return String(cString: base)
        }
    }

    private nonisolated static func startDate(of pid: Int32) -> Date {
        var info = proc_bsdinfo()
        let read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info,
                                Int32(MemoryLayout<proc_bsdinfo>.size))
        guard read > 0 else { return Date() }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec))
    }

    // MARK: Arrêt

    /// Demande poliment, d'abord. `SIGTERM` laisse un serveur fermer ses
    /// connexions et retirer son fichier de verrou ; `SIGKILL` ne laisse rien.
    nonisolated static func stop(_ pid: Int32) -> Bool {
        kill(pid, SIGTERM) == 0
    }

    nonisolated static func force(_ pid: Int32) -> Bool {
        kill(pid, SIGKILL) == 0
    }

    nonisolated static func alive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// L'adresse du Mac sur le réseau local — celle qu'il faut taper sur un
    /// téléphone pour ouvrir le site en cours.
    nonisolated static func localAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var best: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let address = pointer.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }

            let name = String(cString: pointer.pointee.ifa_name)
            let value = text(host)
            // en0 d'abord : c'est le Wi-Fi ou l'Ethernet, pas un tunnel VPN ni
            // un pont Docker.
            if name == "en0" { return value }
            if best == nil, name.hasPrefix("en") { best = value }
        }
        return best
    }
}
