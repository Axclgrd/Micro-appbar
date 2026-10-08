import Commun
import AppKit
import Observation

@MainActor
@Observable
public final class PurgeStore {

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tout"
        case safe = "Sans impact"
        case projects = "Projets"
        case caches = "Caches"
        var id: String { rawValue }
    }

    private(set) var findings: [Finding] = []
    private(set) var scanning = false
    private(set) var progressDone = 0
    private(set) var progressTotal = 0
    private(set) var report: String?
    private(set) var failures: [String] = []
    private(set) var hasScanned = false

    var selection: Set<String> = []
    var focus: Finding?
    var filter: Filter = .all
    var includeCaches = true {
        didSet { UserDefaults.standard.set(includeCaches, forKey: Self.cachesKey) }
    }
    private(set) var roots: [URL]

    private var task: Task<Void, Never>?

    private static let rootsKey = "roots"
    private static let cachesKey = "includeCaches"

    public init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.rootsKey) ?? []
        roots = saved.isEmpty
            ? [FileManager.default.homeDirectoryForCurrentUser]
            : saved.map { URL(fileURLWithPath: $0) }
        includeCaches = UserDefaults.standard.object(forKey: Self.cachesKey) as? Bool ?? true
    }

    /// La ligne d'état lue par la trousse. Exposer `findings` obligerait à
    /// rendre publique toute la mécanique interne pour n'en afficher qu'un
    /// résumé.
    public var headline: String {
        if scanning { return "analyse…" }
        guard hasScanned else { return "" }
        guard !findings.isEmpty else { return "rien à récupérer" }
        return total.formatted(.byteCount(style: .file))
    }

    // MARK: Dossiers analysés

    func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Analyser"
        panel.message = "Choisis un dossier à passer au peigne fin."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !roots.contains(url) {
            roots.append(url)
        }
        saveRoots()
    }

    func removeRoot(_ url: URL) {
        roots.removeAll { $0 == url }
        saveRoots()
    }

    private func saveRoots() {
        UserDefaults.standard.set(roots.map(\.path), forKey: Self.rootsKey)
    }

    // MARK: Analyse

    func scan() {
        task?.cancel()
        findings = []
        selection = []
        failures = []
        report = nil
        focus = nil
        scanning = true
        hasScanned = true
        progressDone = 0
        progressTotal = 0

        let roots = roots
        let includeCaches = includeCaches
        task = Task { [weak self] in
            for await event in Scanner().scan(roots: roots, includeCaches: includeCaches) {
                guard let self else { return }
                switch event {
                case .candidates(let count):
                    self.progressTotal = count
                case .progress(let done, let total):
                    self.progressDone = done
                    self.progressTotal = total
                case .found(let finding):
                    self.insert(finding)
                case .finished:
                    break
                }
            }
            self?.scanning = false
        }
    }

    func cancel() {
        task?.cancel()
        scanning = false
    }

    /// Insertion triée par taille : la liste est utile pendant l'analyse, pas
    /// seulement à la fin, et ce qui compte est toujours en haut.
    private func insert(_ finding: Finding) {
        let index = findings.firstIndex { $0.size < finding.size } ?? findings.count
        findings.insert(finding, at: index)
        // Ce qui ne casse rien est coché d'office : c'est la réponse par défaut
        // à la question que l'app pose. Le reste attend une décision.
        if finding.rule.impact == .none {
            selection.insert(finding.id)
        }
    }

    // MARK: Sélection

    var visible: [Finding] {
        switch filter {
        case .all:      return findings
        case .safe:     return findings.filter { $0.rule.impact == .none }
        case .projects: return findings.filter { !$0.isGlobal }
        case .caches:   return findings.filter(\.isGlobal)
        }
    }

    var total: Int64 { findings.reduce(0) { $0 + $1.size } }
    var selectedTotal: Int64 {
        findings.reduce(0) { selection.contains($1.id) ? $0 + $1.size : $0 }
    }
    var selectedCount: Int { selection.count }
    /// Octets sélectionnés qui sont partagés par liens durs avec autre chose.
    /// Tant qu'une seule des deux copies subsiste, ils ne sont pas rendus.
    var selectedShared: Int64 {
        findings.reduce(0) { selection.contains($1.id) ? $0 + $1.shared : $0 }
    }

    func toggle(_ finding: Finding) {
        if selection.contains(finding.id) {
            selection.remove(finding.id)
        } else {
            selection.insert(finding.id)
        }
    }

    func selectAll(_ on: Bool) {
        if on {
            selection.formUnion(visible.map(\.id))
        } else {
            selection.subtract(visible.map(\.id))
        }
    }

    func selectSafeOnly() {
        selection = Set(findings.filter { $0.rule.impact == .none }.map(\.id))
    }

    // MARK: Suppression

    func delete() async {
        let targets = findings.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { return }

        let result = await Deleter.remove(targets)
        findings.removeAll { result.removed.contains($0.id) }
        selection.subtract(result.removed)
        failures = result.failures
        focus = nil

        let count = result.removed.count
        report = "\(count) élément\(count > 1 ? "s" : "") supprimé\(count > 1 ? "s" : "") · "
            + "\(result.freed.formatted(.byteCount(style: .file))) récupérés"
    }

    // MARK: Espace libre

    /// Espace libre des volumes concernés : celui du démarrage, plus celui de
    /// chaque racine analysée. C'est la mesure qui donne envie de nettoyer.
    var volumes: [(name: String, free: Int64)] {
        var seen: Set<String> = []
        var result: [(String, Int64)] = []

        for url in [URL(fileURLWithPath: "/")] + roots {
            guard let values = try? url.resourceValues(forKeys: [
                .volumeNameKey, .volumeAvailableCapacityForImportantUsageKey, .volumeURLKey,
            ]),
                let name = values.volumeName,
                let free = values.volumeAvailableCapacityForImportantUsage,
                seen.insert(name).inserted
            else { continue }
            result.append((name, free))
        }
        return result
    }
}
