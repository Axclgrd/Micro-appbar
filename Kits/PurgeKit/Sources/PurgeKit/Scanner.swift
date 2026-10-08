import Commun
import Foundation

/// Un artefact trouvé sur le disque, avec de quoi décider de son sort.
struct Finding: Identifiable, Sendable, Hashable {
    let id: String          // le chemin : un artefact ne peut apparaître deux fois
    let url: URL
    let rule: Rule
    /// Le nom du projet auquel il appartient — c'est ce que l'utilisateur
    /// reconnaît, pas le chemin complet.
    let project: String
    let size: Int64
    /// Part de `size` occupée par des fichiers ayant plusieurs liens durs,
    /// donc partagée avec un autre dossier. Voir `Scanner.measure`.
    let shared: Int64
    let files: Int
    let modified: Date?
    /// Commande de reconstruction, quand le projet permet de la deviner.
    let command: String?
    let isGlobal: Bool
}

enum ScanEvent: Sendable {
    /// Le repérage est fini : on sait combien de dossiers restent à peser.
    case candidates(Int)
    case progress(done: Int, total: Int)
    case found(Finding)
    case finished
}

/// Parcours du disque à la recherche d'artefacts régénérables.
///
/// Deux temps, parce que les deux n'ont pas du tout le même coût : repérer les
/// dossiers prend quelques dizaines de millisecondes, les peser prend des
/// minutes. Le repérage donne donc immédiatement le nombre d'éléments, puis la
/// pesée avance en parallèle et publie chaque résultat dès qu'il tombe.
struct Scanner: Sendable {

    /// Nombre de pesées simultanées, à chaque niveau : quatre dossiers pesés
    /// de front, chacun découpé en quatre fils. Tout ici est bloqué sur des
    /// `stat`, jamais sur le processeur.
    private static let workers = 4

    /// Profondeur maximale sous une racine. Un artefact de projet vit à deux ou
    /// trois niveaux ; au-delà, on ne fait plus que payer des `stat`.
    private static let maxDepth = 8

    /// Dossiers dans lesquels on n'entre jamais.
    ///
    /// `Library` est exclu du parcours général parce qu'il est immense et que
    /// ses caches sont déjà traités un par un, avec leur explication.
    private static let skipped: Set<String> = [
        ".git", ".hg", ".svn", "Library", "Applications", ".Trash", ".Trashes",
        ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
        ".TemporaryItems", ".PKInstallSandboxManager",
    ]

    /// Un dossier repéré, pas encore pesé.
    private struct Candidate: Sendable {
        let url: URL
        let rule: Rule
        let project: String
        let command: String?
        let isGlobal: Bool
    }

    func scan(roots: [URL], includeCaches: Bool) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                var candidates: [Candidate] = includeCaches
                    ? Self.globalCandidates() + Self.pnpmCandidates(roots: roots)
                    : []
                for root in roots {
                    if Task.isCancelled { break }
                    candidates.append(contentsOf: Self.walk(root))
                }
                continuation.yield(.candidates(candidates.count))

                await Self.weigh(candidates, continuation: continuation)

                continuation.yield(.finished)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Repérage

    private static func walk(_ root: URL) -> [Candidate] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        // Les artefacts les plus lourds sont des dossiers cachés (`.next`,
        // `.build`) : on ne peut pas se contenter des entrées visibles.
        // `skipsPackageDescendants` évite d'entrer dans les .app et les
        // photothèques, qui n'ont rien à donner.
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }   // un dossier interdit n'arrête pas l'analyse
        ) else { return [] }

        let rootDepth = root.pathComponents.count
        var found: [Candidate] = []

        for case let url as URL in enumerator {
            if Task.isCancelled { return found }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

            let name = url.lastPathComponent
            if skipped.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if url.pathComponents.count - rootDepth >= maxDepth {
                enumerator.skipDescendants()
                continue
            }

            guard let rule = Catalog.project.first(where: { $0.matches(directoryAt: url) }) else {
                continue
            }

            let parent = url.deletingLastPathComponent()
            found.append(Candidate(
                url: url,
                rule: rule,
                project: parent.lastPathComponent,
                command: command(for: rule, in: parent),
                isGlobal: false
            ))

            // Rien d'intéressant sous un artefact : on remonte.
            enumerator.skipDescendants()
        }
        return found
    }

    private static func globalCandidates() -> [Candidate] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Catalog.caches.compactMap { path, rule in
            let url = home.appending(path: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return Candidate(url: url, rule: rule, project: "Cache global",
                             command: nil, isGlobal: true)
        }
    }

    /// Les magasins pnpm, jugés un par un.
    ///
    /// pnpm en sème plusieurs au fil des ans : l'emplacement par défaut a
    /// changé (`~/.pnpm-store` puis `~/Library/pnpm/store`), le format aussi
    /// (`v3` puis `v10`), et un magasin supplémentaire apparaît à la racine du
    /// disque des projets quand celui qui est configuré vit sur un autre
    /// volume. Les traiter comme un motif fixe reviendrait à annoncer « à
    /// reconstruire » pour des dossiers que plus aucune commande ne sait
    /// ouvrir.
    private static func pnpmCandidates(roots: [URL]) -> [Candidate] {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let configured = configuredStore() ?? home.appending(path: "Library/pnpm/store")

        var locations: [URL] = [
            configured,
            home.appending(path: "Library/pnpm/store"),
            home.appending(path: ".pnpm-store"),
        ]
        for root in roots {
            if let volume = (try? root.resourceValues(forKeys: [.volumeURLKey]))?.volume {
                locations.append(volume.appending(path: ".pnpm-store"))
            }
        }

        // Un dossier de version par magasin : `v3`, `v10`…
        var seen: Set<String> = []
        var stores: [(url: URL, location: URL, version: Int)] = []
        for location in locations {
            let path = location.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            let children = (try? manager.contentsOfDirectory(
                at: location, includingPropertiesForKeys: nil, options: [])) ?? []
            for child in children {
                let name = child.lastPathComponent
                guard name.hasPrefix("v"), let version = Int(name.dropFirst()) else { continue }
                stores.append((child, location, version))
            }
        }

        guard let newest = stores.map(\.version).max() else { return [] }
        let configuredPath = configured.standardizedFileURL.path

        return stores.map { store in
            let state: Catalog.StoreState
            if store.version < newest {
                state = .oldFormat(newest: "v\(newest)")
            } else if store.location.standardizedFileURL.path != configuredPath {
                state = .elsewhere(configured: shorten(configured, home: home))
            } else {
                state = .active
            }

            return Candidate(
                url: store.url,
                rule: Catalog.pnpmStore(
                    display: shorten(store.url, home: home),
                    version: "v\(store.version)",
                    state: state),
                project: "Magasin pnpm",
                command: nil,
                isGlobal: true
            )
        }
    }

    /// `store-dir`, tel que pnpm le lit : son propre fichier de configuration
    /// d'abord, le `.npmrc` global ensuite.
    private static func configuredStore() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let files = [
            home.appending(path: "Library/Preferences/pnpm/rc"),
            home.appending(path: ".config/pnpm/rc"),
            home.appending(path: ".npmrc"),
        ]
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces) == "store-dir"
                else { continue }
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "~", with: home.path)
                return URL(fileURLWithPath: value)
            }
        }
        return nil
    }

    private static func shorten(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home.path) ? "~" + path.dropFirst(home.path.count) : path
    }

    // MARK: Pesée

    private static func weigh(
        _ candidates: [Candidate],
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: Finding?.self) { group in
            var next = 0
            var done = 0

            func submit() {
                guard next < candidates.count else { return }
                let candidate = candidates[next]
                next += 1
                group.addTask { await measure(candidate) }
            }

            for _ in 0..<min(workers, candidates.count) { submit() }

            for await finding in group {
                done += 1
                if let finding, finding.size > 0 {
                    continuation.yield(.found(finding))
                }
                continuation.yield(.progress(done: done, total: candidates.count))

                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                submit()
            }
        }
    }

    /// Le total d'un sous-arbre.
    private struct Tally: Sendable {
        var size: Int64 = 0
        var files = 0
        var shared: Int64 = 0

        static func += (lhs: inout Tally, rhs: Tally) {
            lhs.size += rhs.size
            lhs.files += rhs.files
            lhs.shared += rhs.shared
        }
    }

    private static func measure(_ candidate: Candidate) async -> Finding? {
        let tally = await split(candidate.url)
        guard !Task.isCancelled else { return nil }

        return Finding(
            id: candidate.url.path,
            url: candidate.url,
            rule: candidate.rule,
            project: candidate.project,
            size: tally.size,
            shared: tally.shared,
            files: tally.files,
            modified: (try? candidate.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate,
            command: candidate.command,
            isGlobal: candidate.isGlobal
        )
    }

    /// Découpe un sous-arbre en unités de travail parallélisables.
    ///
    /// Sans ça, un seul dossier peut monopoliser toute l'analyse : le magasin
    /// pnpm dépasse le million de fichiers, et une pesée à la file y passe une
    /// minute pendant que les autres fils dorment. Le hic, c'est que sa
    /// ramification utile est trois niveaux plus bas (`store/v10/files/00…ff`).
    /// On descend donc jusqu'à avoir de quoi occuper tout le monde, au lieu de
    /// se fier à la forme du premier niveau.
    private static func units(under url: URL, target: Int) -> [URL] {
        var units = [url]
        var depth = 0

        while units.count < target, depth < 4 {
            var expanded: [URL] = []
            var changed = false
            for unit in units {
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: unit, includingPropertiesForKeys: nil, options: [])) ?? []
                if children.count > 1 {
                    expanded.append(contentsOf: children)
                    changed = true
                } else {
                    expanded.append(unit)
                }
            }
            guard changed else { break }
            units = expanded
            depth += 1
        }
        return units
    }

    private static func split(_ url: URL) async -> Tally {
        let work = units(under: url, target: workers * 4)
        guard work.count > 1 else { return walkTally(url) }

        return await withTaskGroup(of: Tally.self) { group in
            var next = 0
            var result = Tally()

            func submit() {
                guard next < work.count else { return }
                let unit = work[next]
                next += 1
                group.addTask { walkTally(unit) }
            }

            for _ in 0..<min(workers, work.count) { submit() }

            for await tally in group {
                result += tally
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                submit()
            }
            return result
        }
    }

    /// Taille réellement occupée sur le disque, nombre de fichiers, et part
    /// partagée.
    ///
    /// `totalFileAllocatedSize` plutôt que la taille logique : c'est l'espace
    /// qu'on va récupérer, blocs partiels et forks compris.
    ///
    /// La part partagée compte les fichiers ayant plus d'un lien dur. C'est le
    /// cas du magasin pnpm quand il vit sur le même volume que les projets :
    /// ses fichiers sont alors *les mêmes* que ceux des `node_modules`. Sans
    /// cette distinction, l'app additionnerait deux fois les mêmes octets et
    /// promettrait un espace qu'elle ne peut pas rendre. (Sur deux volumes
    /// différents, pnpm recopie : la part partagée est nulle, et les deux
    /// totaux sont bien réels.)
    private static func walkTally(_ url: URL) -> Tally {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .isRegularFileKey, .linkCountKey,
        ]
        var tally = Tally()

        func account(_ values: URLResourceValues) {
            guard values.isRegularFile == true else { return }
            let bytes = Int64(values.totalFileAllocatedSize ?? 0)
            tally.size += bytes
            tally.files += 1
            if (values.linkCount ?? 1) > 1 { tally.shared += bytes }
        }

        // Un enfant peut être un fichier posé à la racine du cache : pas de
        // sous-arbre à parcourir, mais des octets à compter quand même.
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            account(values)
            return tally
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return tally }

        for case let file as URL in enumerator {
            if Task.isCancelled { return tally }
            guard let values = try? file.resourceValues(forKeys: keys) else { continue }
            account(values)
        }
        return tally
    }

    /// La commande exacte qui remet le projet d'aplomb. On la déduit du lock
    /// file : proposer `npm install` à un projet pnpm est pire que de ne rien
    /// proposer du tout.
    private static func command(for rule: Rule, in parent: URL) -> String? {
        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: parent.appending(path: name).path)
        }

        switch rule.id {
        case "node_modules":
            if exists("pnpm-lock.yaml") { return "pnpm install" }
            if exists("yarn.lock") { return "yarn install" }
            if exists("bun.lockb") || exists("bun.lock") { return "bun install" }
            return "npm install"
        case "pods":      return "pod install"
        case "composer":  return "composer install"
        case "terraform": return "terraform init"
        case "venv":
            return exists("pyproject.toml")
                ? "python3 -m venv .venv && pip install -e ."
                : "python3 -m venv .venv && pip install -r requirements.txt"
        default:
            return nil
        }
    }
}
