import Commun
import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
public final class BandeStore {
    /// Une seule file d'attente pour l'app entière : la fenêtre et les vidéos
    /// lâchées sur l'icône du Dock alimentent la même liste.
    public static let shared = BandeStore()

    struct Job: Identifiable {
        let id = UUID()
        let source: URL
        var probe: Probe?
        var state: State = .waiting
        var output: Output?
        var message: String?
        /// L'étape en cours, quand il y en a plusieurs. Une transcription
        /// extrait, télécharge parfois un modèle, puis écoute : une barre qui
        /// avance sans dire de quoi laisse croire à une seule longue attente.
        var stage: String?

        var name: String { source.lastPathComponent }
    }

    enum State: Equatable {
        case waiting
        case running(Double)
        case done
        case failed

        var isPending: Bool { self == .waiting }
        var isRunning: Bool { if case .running = self { true } else { false } }
    }

    private(set) var jobs: [Job] = []
    private var busy = false
    private var current: Task<Void, Never>?

    var format: Format = .text {
        didSet { UserDefaults.standard.set(format.rawValue, forKey: Self.formatKey) }
    }

    /// `nil` — le fichier sort à côté de la vidéo, ce qui est ce qu'on veut
    /// neuf fois sur dix. Un dossier fixe sert quand la source est en lecture
    /// seule : disque de sauvegarde, image disque, partage réseau.
    private(set) var folder: URL? {
        didSet { UserDefaults.standard.set(folder?.path, forKey: Self.folderKey) }
    }

    private static let formatKey = "format"
    private static let folderKey = "folder"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.formatKey),
           let saved = Format(rawValue: raw) {
            format = saved
        }
        if let path = UserDefaults.standard.string(forKey: Self.folderKey) {
            folder = URL(fileURLWithPath: path)
        }
    }

    // MARK: Ce qui rentre

    public func add(_ urls: [URL]) {
        let videos = urls.flatMap(expand)
        guard !videos.isEmpty else { return }
        for url in videos {
            let job = Job(source: url)
            jobs.append(job)
            inspect(job.id)
        }
        pump()
    }

    /// Un dossier lâché sur la fenêtre vaut « toutes les vidéos qui sont
    /// dedans » — sans descendre plus bas, pour ne pas ratisser une
    /// arborescence entière sur un geste.
    private func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles])) ?? []
        return children.filter(isMedia).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func isMedia(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .audiovisualContent) || type.conforms(to: .movie)
    }

    public func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audiovisualContent, .movie, .video]
        panel.prompt = "Extraire"
        panel.message = "Choisis une ou plusieurs vidéos."
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Déposer ici"
        panel.message = "Où ranger les fichiers audio ?"
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        folder = url
    }

    func resetFolder() { folder = nil }

    // MARK: Ce qui sort

    func remove(_ id: Job.ID) {
        if jobs.first(where: { $0.id == id })?.state.isRunning == true { cancel() }
        jobs.removeAll { $0.id == id }
    }

    /// Ne vide que ce qui est terminé : une file en cours ne disparaît pas sous
    /// les doigts.
    func clearFinished() {
        jobs.removeAll { $0.state == .done || $0.state == .failed }
    }

    func retry(_ id: Job.ID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .waiting
        jobs[index].message = nil
        jobs[index].output = nil
        jobs[index].stage = nil
        pump()
    }

    func cancel() {
        current?.cancel()
    }

    func reveal(_ job: Job) {
        guard let url = job.output?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Analyse

    /// La lecture des métadonnées est immédiate et sans effet de bord : chaque
    /// ligne annonce son codec et sa durée avant même que son tour arrive.
    private func inspect(_ id: Job.ID) {
        guard let source = jobs.first(where: { $0.id == id })?.source else { return }
        Task { [weak self] in
            let probe = try? await Extractor.inspect(source)
            guard let self, let index = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[index].probe = probe
        }
    }

    // MARK: File d'attente

    /// Une extraction à la fois. En paralléliser deux ne gagne rien — le disque
    /// est le goulot — et rendrait l'avancement illisible.
    private func pump() {
        guard !busy, let index = jobs.firstIndex(where: { $0.state.isPending }) else { return }
        busy = true
        let job = jobs[index]
        jobs[index].state = .running(0)
        let format = format
        let folder = folder

        current = Task { [weak self] in
            guard let self else { return }
            let id = job.id
            do {
                let output = try await Extractor.extract(job.source, to: format, in: folder) { stage in
                    Task { @MainActor in self.announce(id, stage) }
                } progress: { value in
                    Task { @MainActor in self.advance(id, value) }
                }
                succeed(id, output)
            } catch is CancellationError {
                fail(id, "Annulé.")
            } catch {
                fail(id, error.localizedDescription)
            }
            busy = false
            pump()
        }
    }

    private func announce(_ id: Job.ID, _ stage: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state.isRunning else { return }
        jobs[index].stage = stage
    }

    private func advance(_ id: Job.ID, _ value: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state.isRunning else { return }
        jobs[index].state = .running(value)
    }

    private func succeed(_ id: Job.ID, _ output: Output) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .done
        jobs[index].output = output
        jobs[index].stage = nil
    }

    private func fail(_ id: Job.ID, _ message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .failed
        jobs[index].message = message
        jobs[index].stage = nil
    }

    // MARK: Résumé

    var working: Bool { jobs.contains { $0.state.isRunning || $0.state.isPending } }

    public var summary: String {
        let done = jobs.filter { $0.state == .done }
        let failed = jobs.filter { $0.state == .failed }.count
        let pending = jobs.filter { $0.state.isPending || $0.state.isRunning }.count

        var parts: [String] = []
        if !done.isEmpty {
            let bytes = done.reduce(Int64(0)) { $0 + ($1.output?.bytes ?? 0) }
            parts.append("\(done.count) extrait\(done.count > 1 ? "s" : "") · \(bytes.formatted(.byteCount(style: .file)))")
        }
        if pending > 0 { parts.append("\(pending) en attente") }
        if failed > 0 { parts.append("\(failed) en échec") }
        return parts.joined(separator: "  ·  ")
    }
}
