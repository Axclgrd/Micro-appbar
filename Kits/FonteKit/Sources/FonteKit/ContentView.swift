import Commun
import SwiftUI

/// La fenêtre de Fonte, bâtie comme celle de Purge : l'historique dans la
/// barre latérale, la capture et les propositions au centre, la fiche de la
/// police choisie dans l'inspecteur, et la capture dans une barre flottante.
///
/// Le verre n'habille que ce qui flotte — la barre d'action du bas. La
/// capture et les fiches sont du contenu, sur des surfaces discrètes. Une
/// seule action est teintée : « Capturer ».
public struct ContentView: View {
    @Bindable var store: FonteStore

    public init(store: FonteStore) { self.store = store }

    @State private var inspecting = true
    @State private var focus: Candidate.ID?
    @State private var dropping = false
    @State private var installed: Candidate.ID?

    /// Hauteur réservée aux pastilles de fenêtre. La barre de titre est
    /// transparente et le contenu passe dessous, comme dans Purge.
    private let bandeau: CGFloat = 52

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(height: bandeau - 12)
                sidebar.listStyle(.sidebar)
            }
            .frame(width: 230)
            .background(.regularMaterial)
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            }
            .frame(minWidth: 440, maxWidth: .infinity)
            if inspecting {
                Divider()
                VStack(spacing: 0) {
                    Color.clear.frame(height: bandeau - 12)
                    inspector
                }
                .frame(width: 300)
            }
        }
        .frame(minWidth: 860, minHeight: 540)
        .background(.background)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: store.selection) { _, _ in focus = nil }
        .dropDestination(for: URL.self) { urls, _ in
            store.open(urls)
            return !urls.isEmpty
        } isTargeted: { dropping = $0 }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Barre d'outils

    /// Le titre et l'état à gauche, les actions à droite — comme Purge.
    private var toolbar: some View {
        HStack(spacing: Espace.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Fonte").font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Espace.s)

            Button {
                store.choose()
            } label: {
                Label("Ouvrir une image", systemImage: "photo.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .help("Analyser une image (⌘O)")

            Button {
                if let analysis = store.selected { store.retry(analysis) }
            } label: {
                Label("Réanalyser", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Réanalyser la capture (⌘R)")
            .disabled(store.selected == nil || store.selected?.isAnalyzing == true)

            Button {
                inspecting.toggle()
            } label: {
                Label("Inspecteur", systemImage: "sidebar.right")
            }
            .help(inspecting ? "Masquer l'inspecteur" : "Afficher l'inspecteur")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, Espace.l)
        .frame(height: bandeau)
    }

    private var subtitle: String {
        guard let analysis = store.selected else {
            return "Sélectionne du texte à l'écran, Claude reconnaît la police."
        }
        switch analysis.state {
        case .analyzing:
            return "Analyse en cours…"
        case .failed:
            return "Analyse échouée"
        case .done(let verdict):
            guard let best = verdict.best else { return "Aucune police reconnue" }
            return "\(best.family) · \(best.confidence) % · \(analysis.date.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    // MARK: Historique

    private var sidebar: some View {
        List(selection: $store.selection) {
            ForEach(store.analyses) { analysis in
                row(analysis)
                    .tag(analysis.id)
                    .contextMenu {
                        if let best = analysis.verdict?.best {
                            Button("Copier « \(best.family) »") { store.copy(best.family) }
                        }
                        Button("Réanalyser") { store.retry(analysis) }
                            .disabled(analysis.isAnalyzing)
                        Divider()
                        Button("Supprimer", role: .destructive) { store.remove(analysis) }
                    }
            }
        }
        .onDeleteCommand {
            if let analysis = store.selected { store.remove(analysis) }
        }
        .overlay(alignment: .topLeading) {
            if store.analyses.isEmpty {
                Text("Les captures analysées s'affichent ici.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
        }
    }

    private func row(_ analysis: Analysis) -> some View {
        HStack(spacing: 10) {
            Thumbnail(image: store.image(analysis), width: 52, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(analysis.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(rowDetail(analysis))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func rowDetail(_ analysis: Analysis) -> String {
        switch analysis.state {
        case .analyzing: return store.steps[analysis.id] ?? "Claude examine…"
        case .failed: return "À réessayer"
        case .done(let verdict):
            let when = analysis.date.formatted(.relative(presentation: .named))
            guard let best = verdict.best else { return when }
            return "\(best.confidence) % · \(when)"
        }
    }

    // MARK: Analyse

    @ViewBuilder
    private var detail: some View {
        if let analysis = store.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    capture(analysis)
                    switch analysis.state {
                    case .analyzing: analyzing(analysis)
                    case .failed(let reason): failure(analysis, reason)
                    case .done(let verdict): result(verdict)
                    }
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        } else {
            ContentUnavailableView {
                Label("Aucune capture", systemImage: "textformat")
            } description: {
                Text("Sélectionne du texte à l'écran avec \(store.shortcut.label) : Claude reconnaît la police. Une image glissée ici marche aussi.")
            } actions: {
                Button("Ouvrir une image…") { store.choose() }
            }
        }
    }

    /// La capture telle qu'elle a été prise. Elle peut grandir jusqu'au double
    /// de sa taille réelle — un texte de 12 pt se lit mal autrement — mais
    /// jamais au-delà : un agrandissement flou n'apprend rien sur la police.
    private func capture(_ analysis: Analysis) -> some View {
        Group {
            if let image = store.image(analysis) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width * 2, maxHeight: min(image.size.height * 2, 260))
                    .clipShape(.rect(cornerRadius: Espace.rayon - Espace.s, style: .continuous))
            } else {
                Label("Image introuvable", systemImage: "photo")
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Espace.s)
        .surface()
    }

    private func analyzing(_ analysis: Analysis) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.steps[analysis.id] ?? "Claude examine les lettres…").font(.headline)
                Text("Une quinzaine de secondes : Claude propose des polices. La vérification sur les vraies polices se lance à part.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failure(_ analysis: Analysis, _ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("L'analyse n'a pas abouti").font(.headline)
            }
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Réessayer") { store.retry(analysis) }
                .controlSize(.small)
        }
    }

    private func result(_ verdict: Verdict) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verdict.classification.capitalizingFirst)
                    .font(.title2.weight(.semibold))
                if !verdict.text.isEmpty {
                    Text("« \(verdict.text) »")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            VStack(spacing: 8) {
                ForEach(Array(verdict.candidates.enumerated()), id: \.offset) { rank, candidate in
                    card(candidate, rank: rank, in: verdict)
                }
            }

            if !verdict.note.isEmpty {
                Label(verdict.note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if verdict.verified != true, let analysis = store.selected {
                verifyRow(analysis)
            }
        }
    }

    /// La vérification n'est jamais automatique : c'est un second appel à
    /// Claude, avec une image par police, donc plus coûteux que l'analyse.
    private func verifyRow(_ analysis: Analysis) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if store.verifying.contains(analysis.id) {
                ProgressView().controlSize(.small)
                Text(store.steps[analysis.id] ?? "Claude compare avec les vraies polices…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    store.verify(analysis)
                } label: {
                    Label("Vérifier avec Claude", systemImage: "checkmark.seal")
                }
                .controlSize(.small)
                Text("Un second appel à Claude, qui compare avec les vraies polices. Plus coûteux que l'analyse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    /// Une proposition : son nom, sa probabilité, et — si on a pu se procurer
    /// la police — le texte de la capture recomposé dans son dessin, pour
    /// comparer à l'œil.
    private func card(_ candidate: Candidate, rank: Int, in verdict: Verdict) -> some View {
        let selected = focused(in: verdict)?.id == candidate.id
        let preview = LocalFonts.font(for: candidate, size: rank == 0 ? 30 : 24)
        let radius = Espace.rayon + 2

        return Button {
            focus = candidate.id
            inspecting = true
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(candidate.family)
                        .font(rank == 0 ? .title3.weight(.semibold) : .headline)
                        .lineLimit(1)
                    Pill(text: candidate.license.label, color: candidate.license.color)
                    if candidate.origin != nil, verdict.verified == true {
                        Pill(text: "Comparée", color: .accentColor)
                    }
                    Spacer(minLength: 8)
                    Text("\(candidate.confidence) %")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(rank == 0 ? .primary : .secondary)
                }

                Text([candidate.foundry, candidate.style].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressView(value: Double(min(max(candidate.confidence, 0), 100)), total: 100)
                    .progressViewStyle(.linear)
                    .tint(rank == 0 ? Color.accentColor : Color.secondary)

                if let preview {
                    Text(verdict.sample)
                        .font(preview)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 2)
                } else {
                    Text(candidate.license == .commercial
                         ? "Police payante : pas d'aperçu sans son fichier."
                         : "Aperçu indisponible : police introuvable.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(Espace.m)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: radius))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
    }

    private func focused(in verdict: Verdict) -> Candidate? {
        verdict.candidates.first { $0.id == focus } ?? verdict.best
    }

    // MARK: Fiche

    @ViewBuilder
    private var inspector: some View {
        if let verdict = store.selected?.verdict, let candidate = focused(in: verdict) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.family)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)
                        Text([candidate.foundry, candidate.style].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Pill(text: candidate.license.label, color: candidate.license.color)
                            Pill(text: "\(candidate.confidence) %", color: .secondary)
                            if LocalFonts.isInstalled(candidate) {
                                Pill(text: "Installée", color: .secondary)
                            }
                        }
                    }

                    section("Ce qui la désigne", candidate.evidence)

                    section("Vérification", verification(candidate, verified: verdict.verified == true))

                    if let font = LocalFonts.font(for: candidate, size: 22) {
                        VStack(alignment: .leading, spacing: 5) {
                            heading("Aperçu")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verdict.sample)
                                Text("ABCDEFGHIJKLM")
                                Text("abcdefghijklm")
                                Text("0123456789 &?!")
                            }
                            .font(font)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .surface()
                        }
                    } else {
                        section("Aperçu", "Fonte n'a pas pu se procurer cette police. Une fois installée sur ce Mac, son aperçu s'affiche ici.")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            store.copy(candidate.family)
                        } label: {
                            Label("Copier le nom", systemImage: "doc.on.doc")
                        }
                        if !LocalFonts.isInstalled(candidate), LocalFonts.downloaded(candidate) != nil {
                            Button {
                                installed = LocalFonts.install(candidate) ? candidate.id : nil
                            } label: {
                                Label(installed == candidate.id ? "Installée" : "Installer la police",
                                      systemImage: installed == candidate.id ? "checkmark" : "square.and.arrow.down")
                            }
                            .disabled(installed == candidate.id)
                            .help("Copie le fichier dans ta bibliothèque de polices : elle sera disponible dans toutes les apps.")
                        }
                        if let source = source(for: candidate) {
                            Button {
                                NSWorkspace.shared.open(source.url)
                            } label: {
                                Label(source.label, systemImage: "safari")
                            }
                        }
                    }
                    .controlSize(.small)

                    if !verdict.alternatives.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            heading("Alternatives libres")
                            ForEach(verdict.alternatives, id: \.self) { name in
                                Button {
                                    if let url = Self.googleFonts(name) { NSWorkspace.shared.open(url) }
                                } label: {
                                    HStack {
                                        Text(name).font(.callout)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .help("Chercher \(name) dans Google Fonts")
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView(
                "Aucune police",
                systemImage: "textformat",
                description: Text("Choisis une proposition pour voir ce qui la désigne, son aperçu et où la trouver."))
        }
    }

    /// Ce que vaut la proposition : vérifiée sur le vrai fichier, ou jugée
    /// sur l'image seule.
    private func verification(_ candidate: Candidate, verified: Bool) -> String {
        guard verified else {
            return candidate.origin != nil
                ? "Pas encore vérifiée : l'avis de Claude repose sur l'image seule. « Vérifier avec Claude » la compare à la vraie police."
                : "Pas encore vérifiée : l'avis de Claude repose sur l'image seule."
        }
        switch candidate.origin {
        case .installed?:
            return "Comparée lettre à lettre à la police installée sur ce Mac."
        case let origin?:
            return "Comparée lettre à lettre au fichier de \(origin.label), téléchargé pour l'analyse."
        case nil:
            return candidate.license == .commercial
                ? "Non comparée : police payante, son fichier est hors d'atteinte. L'avis de Claude repose sur l'image seule."
                : "Non comparée : Fonte ne l'a pas dessinée dans cette vérification. L'avis de Claude repose sur l'image seule."
        }
    }

    /// Où se la procurer. Une police système n'a rien à télécharger : elle
    /// est déjà là, ou livrée avec un autre système.
    private func source(for candidate: Candidate) -> (label: String, url: URL)? {
        switch candidate.license {
        case .system:
            return nil
        case .free:
            return Self.googleFonts(candidate.family).map { ("Ouvrir dans Google Fonts", $0) }
        case .commercial, .unknown:
            var components = URLComponents(string: "https://www.myfonts.com/search")
            components?.queryItems = [URLQueryItem(name: "query", value: candidate.family)]
            return components?.url.map { ("Chercher sur MyFonts", $0) }
        }
    }

    private static func googleFonts(_ family: String) -> URL? {
        var components = URLComponents(string: "https://fonts.google.com/")
        components?.queryItems = [URLQueryItem(name: "query", value: family)]
        return components?.url
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            heading(title)
            Text(body)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Barre du bas

    // MARK: Barre d'action flottante

    /// Posée sur le contenu, qui défile dessous : c'est la couche des
    /// contrôles, donc la seule à recevoir du verre.
    private var actionBar: some View {
        HStack(spacing: Espace.m) {
            if let status = store.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if store.analyzingCount > 0 {
                ProgressView().controlSize(.small)
                Text(store.analyzingCount > 1
                     ? "Claude examine \(store.analyzingCount) captures…"
                     : "Claude examine la capture…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(store.analyses.count) capture\(store.analyses.count > 1 ? "s" : "")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(store.shortcut.label)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)

            Button {
                Task { await store.capture() }
            } label: {
                Label("Capturer", systemImage: "viewfinder")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
            .help("Capturer une zone de l'écran (⌘N)")
            .disabled(store.capturing)
        }
        .padding(.horizontal, Espace.l)
        .padding(.vertical, Espace.m)
        .verre(.rect(cornerRadius: 16))
        .padding(Espace.m)
    }
}

/// Une vignette de capture : rognée plutôt que réduite, pour qu'on y voie des
/// lettres et non une ligne grise.
struct Thumbnail: View {
    let image: NSImage?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

/// Une étiquette : un aplat translucide, jamais de verre — elle vit dans le
/// contenu.
struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

private extension String {
    /// « linéale géométrique » → « Linéale géométrique ».
    var capitalizingFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
