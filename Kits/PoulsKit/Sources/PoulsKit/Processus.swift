import Darwin
import Foundation

// Qui consomme quoi, par application.
//
// Trois décisions tiennent ce fichier.
//
// 1. **`libproc`, pas `ps` ni `top`.** Le `%CPU` de `ps` est une moyenne
//    depuis le lancement du process : un navigateur ouvert depuis trois jours
//    y paraît calme même quand il sature un cœur. La vraie charge instantanée
//    se calcule entre deux relevés de `proc_pid_rusage`, ce que fait cette
//    sonde. Coût mesuré : 5 ms pour mille processus.
//
// 2. **Par application, pas par processus.** Un Chrome ouvert, c'est trente
//    lignes « Google Chrome Helper (Renderer) » dans le Moniteur d'activité.
//    Aucune ne répond à la question posée — « qu'est-ce qui consomme ? ». On
//    remonte donc au bundle `.app` qui les contient, et on additionne.
//
// 3. **Seulement les process de l'utilisateur.** `proc_pid_rusage` refuse ceux
//    de root : environ un cinquième de la liste, les démons du système. Leur
//    charge n'est pas perdue pour autant — elle reste dans le total lu par
//    `Sondes.cpuTicks()`, et le panneau l'affiche sous « Système ». Demander
//    root pour lister des processus serait disproportionné.

/// Relevé brut d'un processus, gardé d'un tour sur l'autre.
private struct Releve {
    /// Temps processeur cumulé, en **unités mach**, pas en nanosecondes.
    let cpu: UInt64
    let disk: UInt64       // octets lus + écrits, cumulés
    let footprint: UInt64
}

/// Combien de nanosecondes vaut une unité de temps mach.
///
/// Le piège de ce fichier. `proc_pid_rusage` est documenté comme rendant des
/// nanosecondes, et c'est vrai — sur Intel, où la base de temps vaut 1:1. Sur
/// Apple Silicon elle vaut 125/3 : une unité y fait 41,67 ns, et prendre le
/// chiffre brut pour des nanosecondes divise toutes les charges par quarante.
/// Vérifié à la mesure : un fil qui brûle un cœur pendant deux secondes rend
/// 47 048 161 unités — 0,024 cœur si on lit des nanosecondes, 0,98 cœur avec
/// la conversion.
private let machToNanos: Double = {
    var base = mach_timebase_info_data_t()
    guard mach_timebase_info(&base) == KERN_SUCCESS, base.denom > 0 else { return 1 }
    return Double(base.numer) / Double(base.denom)
}()

struct ProcessProbe {

    private var previous: [Int32: Releve] = [:]
    private var stamp: Date?
    /// Clé de groupe → nom affiché. `displayName` lit le bundle sur le
    /// disque : une fois par application suffit.
    private var names: [String: String] = [:]

    /// Le relevé courant. Rend `nil` au premier appel : sans relevé précédent,
    /// il n'y a pas de débit à calculer, et afficher une moyenne depuis le
    /// démarrage serait un faux chiffre.
    mutating func sample() -> [AppUsage]? {
        let now = Date()
        var current: [Int32: Releve] = [:]
        current.reserveCapacity(previous.count)

        // Agrégat par application, construit en un seul passage.
        var groups: [String: (name: String, bundle: String?, cpu: Double,
                              memory: UInt64, disk: Double, count: Int)] = [:]

        // La borne haute compte autant que la borne basse. Panneau fermé, la
        // sonde ne tourne pas : à la réouverture, le relevé précédent peut
        // dater de dix minutes, et diviser l'écart par ce laps rendrait la
        // moyenne lissée qu'on reproche à `ps`. Passé dix secondes, le relevé
        // ne sert donc que de nouvelle base.
        let elapsed = stamp.map { now.timeIntervalSince($0) } ?? 0
        let measurable = elapsed > 0.2 && elapsed < 10

        for pid in pids() {
            guard let releve = read(pid) else { continue }
            current[pid] = releve

            let path = path(of: pid)
            guard !path.isEmpty else { continue }
            let key = groupKey(for: path)

            var cpu = 0.0
            var disk = 0.0
            if measurable, let before = previous[pid] {
                // Le temps CPU ne recule jamais, sauf si le pid a été recyclé
                // entre deux tours : on ignore alors le delta plutôt que de
                // publier une pointe inventée.
                if releve.cpu >= before.cpu {
                    let nanos = Double(releve.cpu - before.cpu) * machToNanos
                    cpu = nanos / 1e9 / elapsed / Double(Sondes.cores)
                }
                if releve.disk >= before.disk {
                    disk = Double(releve.disk - before.disk) / elapsed
                }
            }

            if var group = groups[key] {
                group.cpu += cpu
                group.memory += releve.footprint
                group.disk += disk
                group.count += 1
                groups[key] = group
            } else {
                let bundle = key.hasPrefix("/") ? key : nil
                groups[key] = (name: displayName(for: key), bundle: bundle,
                               cpu: cpu, memory: releve.footprint, disk: disk, count: 1)
            }
        }

        previous = current
        stamp = now
        guard measurable else { return nil }

        return groups.map { key, g in
            AppUsage(id: key, name: g.name, bundlePath: g.bundle,
                     cpu: g.cpu, memory: g.memory, disk: g.disk, processes: g.count)
        }
    }

    // MARK: Regroupement

    /// Les démons dont le nom ne dit rien à personne, et ce qu'ils sont.
    ///
    /// Même esprit que les notes de Ports : une table courte, écrite à la
    /// main, qui ne couvre que ce qu'on voit vraiment arriver en tête de liste.
    /// Plusieurs binaires pointant vers le même libellé sont *fusionnés* en une
    /// ligne : Spotlight qui indexe, ce sont quatre processus et une seule
    /// réponse à la question « qu'est-ce qui consomme ? ».
    private static let alias: [String: String] = [
        "corespotlightd":        "Spotlight (indexation)",
        "mds":                   "Spotlight (indexation)",
        "mds_stores":            "Spotlight (indexation)",
        "mdworker_shared":       "Spotlight (indexation)",
        "spotlightknowledged":   "Spotlight (indexation)",
        "com.apple.WebKit.WebContent": "Pages web (WebKit)",
        "com.apple.WebKit.Networking": "Pages web (WebKit)",
        "photoanalysisd":        "Photos (analyse)",
        "photolibraryd":         "Photos (analyse)",
        "backupd":               "Time Machine",
        "bird":                  "iCloud",
        "cloudd":                "iCloud",
        "syncdefaultsd":         "iCloud",
        "swift-frontend":        "Compilation Swift",
        "swift-driver":          "Compilation Swift",
        "SourceKitService":      "Complétion Xcode",
        "XProtectRemediatorBehaviorService": "XProtect (macOS)",
    ]

    /// Les dossiers qui ne nomment rien : traversés quand il faut remonter
    /// jusqu'à un nom lisible.
    private static let contenants: Set<String> = [
        "versions", "bin", "sbin", "libexec", "MacOS", "Contents", "Resources",
        "native-binary", "node_modules", "dist", "build", "usr", "local",
        "share", "lib", "Helpers", "XPCServices", "Frameworks",
    ]

    /// La clé d'une application : le chemin de son bundle, ou le nom du
    /// binaire quand il n'y en a pas (`node`, un démon).
    private func groupKey(for path: String) -> String {
        // Le simulateur lance une cinquantaine de démons iOS sous des noms que
        // personne ne reconnaît (`sociallayerd`, `PosterBoard`…). Pour qui
        // regarde ce qui consomme, c'est « le simulateur », un point.
        if path.contains(".simruntime") || path.contains("/CoreSimulator/") {
            return "alias:Simulateur"
        }
        let binaire = (path as NSString).lastPathComponent
        if let connu = Self.alias[binaire] { return "alias:" + connu }

        let components = (path as NSString).pathComponents
        // Les outils rangés dans Xcode (Simulator, Instruments) sont des apps
        // à part entière : c'est le bundle le plus profond qui les nomme, pas
        // Xcode.app qui les contient.
        let deepest = path.contains("/Developer/Applications/")
        var accumulator: [String] = []
        var found: String?
        for component in components {
            accumulator.append(component)
            guard component.hasSuffix(".app") else { continue }
            found = NSString.path(withComponents: accumulator)
            if !deepest { break }
        }
        if let found { return found }

        // Claude Code s'installe sous `…/claude/versions/2.1.307` : le binaire
        // porte le numéro de version et rien d'autre. Une ligne « 2.1.307 »
        // n'apprend rien, alors on remonte jusqu'au premier dossier qui nomme
        // quelque chose.
        guard binaire.allSatisfy({ $0.isNumber || $0 == "." }) else { return binaire }
        for component in components.dropLast().reversed()
        where component != "/" && !Self.contenants.contains(component)
            && !component.hasPrefix(".") {
            return component
        }
        return binaire
    }

    private mutating func displayName(for key: String) -> String {
        if let known = names[key] { return known }
        let name: String
        if key.hasPrefix("alias:") {
            name = String(key.dropFirst(6))
        } else if key.hasPrefix("/") {
            let display = FileManager.default.displayName(atPath: key)
            name = display.isEmpty ? (key as NSString).lastPathComponent : display
        } else {
            name = key
        }
        names[key] = name
        return name
    }

    // MARK: Lectures

    private func pids() -> [Int32] {
        let size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return [] }
        var buffer = [Int32](repeating: 0, count: Int(size) / MemoryLayout<Int32>.size)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, size)
        guard written > 0 else { return [] }
        return Array(buffer.prefix(Int(written) / MemoryLayout<Int32>.size)).filter { $0 > 0 }
    }

    private func read(_ pid: Int32) -> Releve? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return Releve(
            cpu: info.ri_user_time + info.ri_system_time,
            disk: info.ri_diskio_bytesread + info.ri_diskio_byteswritten,
            // `ri_phys_footprint` est exactement la colonne « Mémoire » du
            // Moniteur d'activité : la mémoire que ce process fait réellement
            // peser sur la machine, compression comprise.
            footprint: info.ri_phys_footprint
        )
    }

    private func path(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
