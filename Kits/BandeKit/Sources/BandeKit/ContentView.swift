import Commun
import SwiftUI

public struct ContentView: View {
    @Bindable var store: BandeStore

    public init(store: BandeStore) { self.store = store }
    @State private var targeted = false

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
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
        .overlay { if targeted { landing } }
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bande").font(.title2.weight(.semibold))
                    Text(tagline)
                        .font(.callout)
                        .foregroundStyle(missingEngine ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                Spacer()
                if store.working {
                    ProgressView().controlSize(.small)
                }
            }

            Picker("", selection: $store.format) {
                ForEach(Format.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        // Le bandeau de titre est masqué : on rend sa place aux pastilles de
        // fenêtre plutôt que d'afficher un titre en double.
        .padding(.top, 30)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    /// La transcription est la seule option qui peut manquer à l'appel : le
    /// dire au moment où on la choisit vaut mieux que de le dire après avoir
    /// laissé l'utilisateur déposer sa vidéo.
    private var missingEngine: Bool {
        store.format == .text && !Transcriber.isSupported
    }

    private var tagline: String {
        if missingEngine {
            return "La transcription demande macOS 26 — ce Mac reste aux deux formats audio."
        }
        return store.jobs.isEmpty && store.format == .original
            ? "Une vidéo entre, son audio sort."
            : store.format.detail
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        if store.jobs.isEmpty {
            empty
        } else {
            List {
                ForEach(store.jobs) { job in
                    row(job)
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            if job.state == .done {
                                Button("Afficher dans le Finder") { store.reveal(job) }
                            }
                            if job.state == .failed {
                                Button("Réessayer") { store.retry(job.id) }
                            }
                            Button("Retirer de la liste") { store.remove(job.id) }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Dépose une vidéo ici")
                .font(.title3.weight(.medium))
            Text(store.format == .text
                 ? "MP4, MOV, M4V — le texte sort à côté du fichier d'origine."
                 : "MP4, MOV, M4V — l'audio sort à côté du fichier d'origine.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choisir une vidéo…") { store.choose() }
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var landing: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .padding(10)
            .allowsHitTesting(false)
    }

    // MARK: Une ligne

    private func row(_ job: BandeStore.Job) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon(job))
                .font(.system(size: 17))
                .foregroundStyle(job.state == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle(job))
                    .font(.caption)
                    .foregroundStyle(job.state == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            trailing(job)
        }
        .padding(.vertical, 4)
    }

    private func icon(_ job: BandeStore.Job) -> String {
        switch job.state {
        case .done:    "checkmark.circle.fill"
        case .failed:  "exclamationmark.triangle.fill"
        case .running: "waveform"
        case .waiting: "film"
        }
    }

    private func subtitle(_ job: BandeStore.Job) -> String {
        switch job.state {
        case .failed:
            return job.message ?? "Échec."
        case .done:
            guard let output = job.output else { return "Terminé." }
            return "\(output.url.lastPathComponent) · \(output.bytes.formatted(.byteCount(style: .file))) · \(output.method.label)"
        default:
            guard let probe = job.probe else { return "Lecture du fichier…" }
            let known = "\(BandeFormat.duration(probe.duration)) · \(probe.summary)"
            guard let stage = job.stage, job.state.isRunning else { return known }
            return "\(known) · \(stage)"
        }
    }

    @ViewBuilder
    private func trailing(_ job: BandeStore.Job) -> some View {
        switch job.state {
        case .running(let value):
            HStack(spacing: 8) {
                ProgressView(value: value).frame(width: 90)
                Button {
                    store.cancel()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("Arrêter")
            }
        case .done:
            Button {
                store.reveal(job)
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .help("Afficher dans le Finder")
        case .failed:
            Button("Réessayer") { store.retry(job.id) }
                .buttonStyle(.link)
                .font(.callout)
        case .waiting:
            Text("en attente")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Pied

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                store.folder == nil ? store.chooseFolder() : store.resetFolder()
            } label: {
                Label(store.folder?.lastPathComponent ?? "À côté de la vidéo",
                      systemImage: store.folder == nil ? "arrow.down.forward.square" : "folder")
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .help(store.folder == nil
                  ? "Le fichier audio est écrit dans le dossier de la vidéo. Cliquer pour choisir un dossier fixe."
                  : "Cliquer pour revenir au dossier de la vidéo.")

            Spacer()

            Text(store.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.jobs.contains(where: { $0.state == .done || $0.state == .failed }) {
                Button("Vider") { store.clearFinished() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
