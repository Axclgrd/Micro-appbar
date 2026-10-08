import AppKit
import Commun
import SwiftUI

public struct ContentView: View {
    @Bindable var store: BandeStore

    public init(store: BandeStore) { self.store = store }

    @State private var targeted = false
    @State private var selection: BandeStore.Job.ID?
    /// La ligne dont le texte vient d'être copié : un coche remplace l'icône
    /// un instant, c'est la seule confirmation dont le geste a besoin.
    @State private var copied: BandeStore.Job.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        // Le contenu part sous la barre de titre (fullSizeContentView) : on ne
        // fixe aucune marge à la main, la zone sûre garde les pastilles de
        // fenêtre à l'écart du sélecteur.
        VStack(spacing: 0) {
            header
            if store.jobs.isEmpty {
                dropZone
            } else {
                queue
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(.background)
        // La fenêtre entière est la cible : viser une zone précise avec un
        // fichier au bout du curseur est un geste inutilement exigeant.
        .dropDestination(for: URL.self) { urls, _ in
            store.add(urls)
            return true
        } isTargeted: { targeted = $0 }
        .overlay { if targeted && !store.jobs.isEmpty { landing } }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: targeted)
        // ⌘O vit aussi dans la vue : la fenêtre ouverte depuis Trousse n'a pas
        // le menu de l'app autonome.
        .background {
            Button("Ouvrir une vidéo…") { store.choose() }
                .keyboardShortcut("o")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: En-tête

    private var header: some View {
        VStack(spacing: Espace.s) {
            Picker("Sortie", selection: $store.format) {
                ForEach(Format.allCases) { format in
                    Text(label(format)).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Format de sortie")
            .help("Ce que Bande produit pour chaque vidéo")

            if missingEngine {
                Label("La transcription demande macOS 26. Ce Mac reste aux deux formats audio.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else {
                Text(store.format.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Espace.l)
        .padding(.top, Espace.s)
        .padding(.bottom, Espace.m)
    }

    /// Des libellés courts : trois segments doivent tenir sur une ligne.
    private func label(_ format: Format) -> String {
        switch format {
        case .text:     "Transcription"
        case .original: "Audio .m4a"
        case .speech:   "WAV 16 kHz"
        }
    }

    /// La transcription est la seule option qui peut manquer à l'appel : le
    /// dire au moment où on la choisit vaut mieux que de le dire après avoir
    /// laissé l'utilisateur déposer sa vidéo.
    private var missingEngine: Bool {
        store.format == .text && !Transcriber.isSupported
    }

    // MARK: Zone de dépôt

    private var dropZone: some View {
        VStack(spacing: Espace.s) {
            Image(systemName: targeted ? "arrow.down.circle.fill" : "waveform")
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
            Text("Dépose des vidéos ici")
                .font(.title3.weight(.medium))
            Text(store.format == .text
                 ? "MP4, MOV, M4V ou un dossier. Le texte sort à côté du fichier d'origine."
                 : "MP4, MOV, M4V ou un dossier. L'audio sort à côté du fichier d'origine.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choisir des vidéos…") { store.choose() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, Espace.s)
                .help("Choisir des vidéos (⌘O)")
        }
        .padding(Espace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? AnyShapeStyle(Color.accentColor.opacity(0.08)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(targeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [7, 5]))
        }
        .padding(.horizontal, Espace.l)
        .padding(.bottom, Espace.m)
        .accessibilityElement(children: .contain)
    }

    /// Pendant un dépôt sur une file déjà remplie : le même retour que la zone
    /// vide, et un mot flottant pour dire ce qui va se passer. Seul élément
    /// en verre — il flotte au-dessus du contenu.
    private var landing: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(0.08))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor, lineWidth: 2)
            Label("Ajouter à la file", systemImage: "plus.circle.fill")
                .font(.headline)
                .padding(.horizontal, Espace.l)
                .padding(.vertical, Espace.s)
                .verre(Capsule())
        }
        .padding(Espace.s)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: File

    private var queue: some View {
        List(selection: $selection) {
            ForEach(store.jobs) { job in
                row(job)
                    .tag(job.id)
                    .contextMenu { menu(job) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // Supprimer retire la ligne choisie, comme dans n'importe quelle liste.
        .onDeleteCommand {
            if let selection { store.remove(selection) }
        }
    }

    @ViewBuilder
    private func menu(_ job: BandeStore.Job) -> some View {
        if job.state == .done {
            Button("Afficher dans le Finder") { store.reveal(job) }
            if textURL(job) != nil {
                Button("Copier le texte") { copy(job) }
            }
        }
        if job.state == .failed {
            Button("Réessayer") { store.retry(job.id) }
        }
        Divider()
        Button("Retirer de la liste") { store.remove(job.id) }
    }

    // MARK: Une ligne

    private func row(_ job: BandeStore.Job) -> some View {
        HStack(spacing: Espace.m) {
            Image(systemName: icon(job))
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint(job))
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle(job))
                    .font(.subheadline)
                    .foregroundStyle(job.state == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                if case .running(let value) = job.state {
                    ProgressView(value: value)
                        .controlSize(.small)
                        .padding(.top, 2)
                        .accessibilityLabel("Progression de \(job.name)")
                }
            }

            Spacer(minLength: Espace.s)

            trailing(job)
        }
        .padding(.vertical, Espace.xs)
        .accessibilityElement(children: .contain)
    }

    private func icon(_ job: BandeStore.Job) -> String {
        switch job.state {
        case .done:    "checkmark.circle.fill"
        case .failed:  "exclamationmark.triangle.fill"
        case .running: "waveform"
        case .waiting: "film"
        }
    }

    private func tint(_ job: BandeStore.Job) -> AnyShapeStyle {
        switch job.state {
        case .done:    AnyShapeStyle(.green)
        case .failed:  AnyShapeStyle(.red)
        case .running: AnyShapeStyle(.tint)
        case .waiting: AnyShapeStyle(.secondary)
        }
    }

    private func subtitle(_ job: BandeStore.Job) -> String {
        switch job.state {
        case .failed:
            return job.message ?? "Échec."
        case .done:
            guard let output = job.output else { return "Terminé." }
            return "\(output.url.lastPathComponent) · \(output.bytes.formatted(.byteCount(style: .file))) · \(output.method.label)"
        case .waiting:
            guard let probe = job.probe else { return "En attente · lecture du fichier…" }
            return "En attente · \(BandeFormat.duration(probe.duration)) · \(probe.summary)"
        case .running:
            guard let probe = job.probe else { return job.stage ?? "Lecture du fichier…" }
            let known = "\(BandeFormat.duration(probe.duration)) · \(probe.summary)"
            guard let stage = job.stage else { return known }
            return "\(stage) · \(known)"
        }
    }

    @ViewBuilder
    private func trailing(_ job: BandeStore.Job) -> some View {
        switch job.state {
        case .running(let value):
            HStack(spacing: Espace.s) {
                Text(value.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button { store.cancel() } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Arrêter")
                .help("Arrêter")
            }
        case .done:
            HStack(spacing: Espace.s) {
                if textURL(job) != nil {
                    Button { copy(job) } label: {
                        Image(systemName: copied == job.id ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copier le texte")
                    .help("Copier le texte")
                }
                Button { store.reveal(job) } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Afficher dans le Finder")
                .help("Afficher dans le Finder")
            }
        case .failed:
            Button("Réessayer") { store.retry(job.id) }
                .controlSize(.small)
                .help("Relancer l'extraction de ce fichier")
        case .waiting:
            Button { store.remove(job.id) } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Retirer de la liste")
            .help("Retirer de la liste")
        }
    }

    // MARK: Texte

    /// Le fichier de transcription d'une ligne terminée, s'il y en a un.
    private func textURL(_ job: BandeStore.Job) -> URL? {
        guard job.state == .done, let url = job.output?.url, url.pathExtension == "txt" else { return nil }
        return url
    }

    private func copy(_ job: BandeStore.Job) {
        guard let url = textURL(job),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = job.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == job.id { copied = nil }
        }
    }

    // MARK: Pied

    private var footer: some View {
        HStack(spacing: Espace.m) {
            Menu {
                Toggle("À côté de la vidéo", isOn: Binding(
                    get: { store.folder == nil },
                    set: { _ in store.resetFolder() }))
                Divider()
                Button(store.folder == nil ? "Choisir un dossier…" : "Dossier : \(store.folder?.lastPathComponent ?? "")…") {
                    store.chooseFolder()
                }
            } label: {
                Label(store.folder?.lastPathComponent ?? "À côté de la vidéo",
                      systemImage: store.folder == nil ? "arrow.down.forward.square" : "folder")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(store.folder == nil
                  ? "Le résultat est écrit dans le dossier de la vidéo. Choisir un dossier fixe."
                  : "Le résultat est écrit dans ce dossier.")

            Spacer()

            Text(store.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)

            if store.jobs.contains(where: { $0.state == .done || $0.state == .failed }) {
                Button("Vider") { store.clearFinished() }
                    .help("Retirer de la liste les fichiers terminés ou en échec")
            }
            if !store.jobs.isEmpty {
                Button("Ajouter…") { store.choose() }
                    .help("Ajouter des vidéos (⌘O)")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, Espace.l)
        .padding(.vertical, Espace.s)
    }
}
