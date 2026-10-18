import AppKit
import Carbon.HIToolbox
import Commun
import Observation
import UniformTypeIdentifiers

/// Les combinaisons proposées pour Fonte : autour du F, loin du T et du G de
/// Grab, pour que les deux outils cohabitent dans Trousse.
extension Shortcut {
    static let all: [Shortcut] = [
        Shortcut(id: "cmd-opt-shift-f", label: "⌥⇧⌘F",
                 keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | optionKey | shiftKey)),
        Shortcut(id: "cmd-ctrl-opt-f", label: "⌃⌥⌘F",
                 keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | controlKey | optionKey)),
        Shortcut(id: "cmd-opt-shift-y", label: "⌥⇧⌘Y",
                 keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(cmdKey | optionKey | shiftKey)),
        Shortcut(id: "cmd-ctrl-opt-y", label: "⌃⌥⌘Y",
                 keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(cmdKey | controlKey | optionKey)),
    ]

    static func named(_ id: String?) -> Shortcut {
        all.first { $0.id == id } ?? all[0]
    }
}

@MainActor
extension Hotkey {
    /// Le raccourci de Fonte ; « FONT » en OSType.
    static let shared = Hotkey(signature: 0x464F4E54)
}

/// Une capture et ce qu'on en sait.
struct Analysis: Identifiable, Codable, Hashable {
    enum State: Codable, Hashable {
        case analyzing
        case done(Verdict)
        case failed(String)
    }

    let id: UUID
    let date: Date
    var state: State

    var verdict: Verdict? {
        if case .done(let verdict) = state { return verdict }
        return nil
    }

    var isAnalyzing: Bool { state == .analyzing }

    /// Le nom à afficher dans une liste.
    var title: String {
        switch state {
        case .analyzing: "Analyse…"
        case .failed: "Échec"
        case .done(let verdict): verdict.best?.family ?? "Police inconnue"
        }
    }
}

/// La capture, l'analyse, et l'historique.
@MainActor
@Observable
public final class FonteStore {

    public static let shared = FonteStore()

    private(set) var analyses: [Analysis] = []
    var selection: Analysis.ID?

    /// Vrai pendant la sélection à l'écran, pas pendant l'analyse : on peut
    /// lancer une deuxième capture pendant que Claude examine la première.
    private(set) var capturing = false
    private(set) var status: String?

    /// L'icône dans la barre de menus. Facultative, comme celle de Grab : le
    /// raccourci suffit, et relancer Fonte la fait revenir.
    var showIcon = true {
        didSet { Shared.defaults.set(!showIcon, forKey: "fonte.hideIcon") }
    }

    var shortcut: Shortcut {
        didSet {
            Shared.defaults.set(shortcut.id, forKey: "fonte.shortcut")
            hotkeyWorks = Hotkey.shared.register(shortcut)
        }
    }

    /// Faux quand la combinaison est déjà prise par une autre app.
    private(set) var hotkeyWorks = true

    /// Une capture a-t-elle *prouvé* que l'autorisation manque ? Même logique
    /// que dans Grab : `CGPreflightScreenCaptureAccess()` garde sa réponse en
    /// cache et se trompe après un octroi, on ne croit donc qu'une capture
    /// réellement revenue noire.
    private(set) var captureDenied = false

    private(set) var claudeAvailable = true

    /// Ouvre la fenêtre. Fournie par le module, qui la possède.
    @ObservationIgnored var present: (() -> Void)?

    @ObservationIgnored private var thumbnails: [UUID: NSImage] = [:]

    /// Le nom de l'app qui héberge l'outil — « Fonte » lancée seule,
    /// « Trousse » quand c'est elle. C'est ce nom-là qu'on coche dans les
    /// Réglages système.
    static var host: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "cette app"
    }

    /// L'étape en cours de chaque analyse : lecture, propositions,
    /// téléchargement, comparaison. Elle n'est pas gardée — elle ne vaut que
    /// pendant l'attente.
    private(set) var steps: [UUID: String] = [:]

    /// Les analyses dont la vérification par Claude est en cours.
    private(set) var verifying: Set<UUID> = []

    var analyzingCount: Int { analyses.filter(\.isAnalyzing).count }
    var latest: Analysis? { analyses.first }
    var selected: Analysis? { analyses.first { $0.id == selection } }

    init() {
        showIcon = !Shared.defaults.bool(forKey: "fonte.hideIcon")
        shortcut = Shortcut.named(Shared.defaults.string(forKey: "fonte.shortcut"))
        hotkeyWorks = Hotkey.shared.register(shortcut)
        Hotkey.shared.onFire = { [weak self] in
            Task { await self?.capture() }
        }
        load()
        selection = analyses.first?.id
        refreshClaude()
        // Les images confiées à Fonte pendant que Trousse l'héberge.
        Shared.observe("fonte.inbox") {
            MainActor.assumeIsolated { FonteStore.shared.collect() }
        }
        collect()
    }

    // MARK: Images reçues

    /// Les images ouvertes avec Fonte — lâchées sur son icône, « Ouvrir
    /// avec », `open -a Fonte`.
    ///
    /// Si Trousse tourne, l'app autonome s'efface aussitôt lancée : elle
    /// dépose les images dans un dossier commun et prévient Trousse, qui les
    /// analyse. Sinon, elle les analyse elle-même.
    public func receive(_ urls: [URL]) {
        guard Presence.shared.trousseIsRunning else {
            open(urls)
            return
        }
        try? FileManager.default.createDirectory(at: Self.inbox, withIntermediateDirectories: true)
        for url in urls {
            try? FileManager.default.copyItem(at: url, to: Self.inbox.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)"))
        }
        Shared.broadcast("fonte.inbox")
    }

    private static var inbox: URL { folder.appending(path: "Arrivée", directoryHint: .isDirectory) }

    /// Seul l'hôte actif ramasse : Trousse quand elle tourne, sinon Fonte.
    /// L'app autonome qui s'efface ne doit pas prendre l'image au passage.
    func collect() {
        guard Bundle.main.bundleIdentifier == Shared.trousseIdentifier || !Presence.shared.trousseIsRunning
        else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.inbox, includingPropertiesForKeys: nil)) ?? []
        guard !files.isEmpty else { return }
        open(files)
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: Capture

    func capture() async {
        guard !capturing else { return }
        capturing = true
        defer { capturing = false }
        status = nil

        // La fenêtre de Fonte masquerait justement ce qu'on veut viser : on
        // l'écarte le temps de la sélection.
        let hid = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if hid { NSApp.hide(nil) }

        let outcome = await Task.detached(priority: .userInitiated) {
            ScreenSelection.run()
        }.value

        if hid { NSApp.unhide(nil) }

        switch outcome {
        case .cancelled:
            status = "Capture annulée."
        case .denied:
            captureDenied = true
            status = "La capture est revenue vide : macOS n'autorise pas \(Self.host) à lire l'écran."
        case .image(let data):
            captureDenied = false
            submit(data)
        }
    }

    /// Une image venue d'ailleurs : glissée dans la fenêtre, ou choisie.
    func open(_ urls: [URL]) {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            submit(data)
        }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choisis une image qui contient du texte."
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    private func submit(_ data: Data) {
        guard let png = Picture.normalized(data) else {
            status = "Ce fichier n'est pas une image lisible."
            return
        }
        let analysis = Analysis(id: UUID(), date: .now, state: .analyzing)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try png.write(to: Self.imageFile(analysis.id))
        } catch {
            status = "Impossible d'enregistrer la capture : \(error.localizedDescription)"
            return
        }
        analyses.insert(analysis, at: 0)
        trim()
        save()
        selection = analysis.id
        present?()
        run(analysis.id, png)
    }

    private func run(_ id: UUID, _ png: Data) {
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Typographer.identify(png) { step in
                    Task { @MainActor in self.steps[id] = step }
                }
            }.value
            steps[id] = nil
            guard let index = analyses.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case .success(let verdict):
                analyses[index].state = .done(verdict)
            case .failure(let failure):
                if case .missing = failure { claudeAvailable = false }
                analyses[index].state = .failed(failure.message)
            }
            save()
        }
    }

    /// Le second appel à Claude, sur demande : compare les meilleures
    /// propositions aux vraies polices. Plus lourd que l'analyse (une image
    /// par police), il ne part jamais seul.
    func verify(_ analysis: Analysis) {
        guard let verdict = analysis.verdict, !verifying.contains(analysis.id), !analysis.isAnalyzing,
              let png = try? Data(contentsOf: Self.imageFile(analysis.id))
        else { return }
        let id = analysis.id
        verifying.insert(id)
        status = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Typographer.verify(png, proposal: verdict) { step in
                    Task { @MainActor in self.steps[id] = step }
                }
            }.value
            verifying.remove(id)
            steps[id] = nil
            guard let index = analyses.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case .success(let better):
                analyses[index].state = .done(better)
                save()
            case .failure(let failure):
                // L'analyse reste : la vérification a échoué, pas la
                // reconnaissance.
                if case .missing = failure { claudeAvailable = false }
                status = failure.message
            }
        }
    }

    func retry(_ analysis: Analysis) {
        guard !analysis.isAnalyzing, !verifying.contains(analysis.id),
              let index = analyses.firstIndex(where: { $0.id == analysis.id }),
              let png = try? Data(contentsOf: Self.imageFile(analysis.id))
        else { return }
        refreshClaude()
        analyses[index].state = .analyzing
        run(analysis.id, png)
    }

    func remove(_ analysis: Analysis) {
        try? FileManager.default.removeItem(at: Self.imageFile(analysis.id))
        thumbnails[analysis.id] = nil
        analyses.removeAll { $0.id == analysis.id }
        if selection == analysis.id { selection = analyses.first?.id }
        save()
    }

    func image(_ analysis: Analysis) -> NSImage? {
        if let cached = thumbnails[analysis.id] { return cached }
        let image = NSImage(contentsOf: Self.imageFile(analysis.id))
        thumbnails[analysis.id] = image
        return image
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Autorisations

    func refreshClaude() {
        claudeAvailable = Typographer.locate() != nil
    }

    /// Un préflight positif efface le refus constaté ; un négatif ne prouve
    /// rien et on l'ignore.
    func refreshPermission() {
        if CGPreflightScreenCaptureAccess() { captureDenied = false }
    }

    /// Une app qui n'a jamais demandé n'apparaît pas dans Réglages système ›
    /// Enregistrement de l'écran : on demande dès l'ouverture du panneau.
    func askQuietly() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        CGRequestScreenCaptureAccess()
        refreshPermission()
    }

    func clearDenial() {
        captureDenied = false
        status = nil
    }

    func requestPermission() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Historique

    /// Partagé entre Fonte et Trousse : une seule des deux tourne à la fois,
    /// et l'historique doit suivre l'outil, pas l'app qui l'héberge.
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Micro-app/Fonte", directoryHint: .isDirectory)
    }

    private static var index: URL { folder.appending(path: "analyses.json") }

    private static func imageFile(_ id: UUID) -> URL {
        folder.appending(path: "\(id.uuidString).png")
    }

    /// Au-delà, les plus anciennes partent. L'historique sert à retrouver la
    /// police vue hier, pas à archiver.
    private static let keep = 60

    private func trim() {
        guard analyses.count > Self.keep else { return }
        for analysis in analyses[Self.keep...] {
            try? FileManager.default.removeItem(at: Self.imageFile(analysis.id))
            thumbnails[analysis.id] = nil
        }
        analyses.removeLast(analyses.count - Self.keep)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.index),
              let stored = try? JSONDecoder().decode([Analysis].self, from: data)
        else { return }
        // Une analyse restée « en cours » a été interrompue par la fermeture
        // de l'app : elle ne finira jamais, autant le dire.
        analyses = stored.map { analysis in
            var analysis = analysis
            if analysis.isAnalyzing { analysis.state = .failed("Analyse interrompue. Réessaie.") }
            return analysis
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(analyses) else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? data.write(to: Self.index, options: .atomic)
    }
}
