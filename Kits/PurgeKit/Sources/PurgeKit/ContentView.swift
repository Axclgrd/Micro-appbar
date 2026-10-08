import AppKit
import Commun
import SwiftUI

/// La fenêtre de Purge, bâtie comme Gestion du stockage ou une liste du
/// Finder : à gauche les catégories et les dossiers analysés, au centre la
/// liste des artefacts avec leur poids, à droite l'inspecteur qui dit ce que
/// chaque suppression coûte. Purge demande avant d'agir : rien n'est supprimé
/// sans une confirmation qui annonce le volume exact.
public struct ContentView: View {
    @Bindable var store: PurgeStore

    public init(store: PurgeStore) { self.store = store }

    @State private var confirming = false
    @State private var deleting = false

    /// Hauteur réservée aux pastilles de fenêtre. La barre de titre est
    /// transparente et le contenu passe dessous : on possède cette zone
    /// plutôt que de dépendre de la zone sûre, qui varie selon l'hôte.
    private let bandeau: CGFloat = 52

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Divider()
            main
                .frame(minWidth: 440, maxWidth: .infinity)
            Divider()
            inspector
                .frame(width: 290)
        }
        .frame(minWidth: 960, minHeight: 580)
        .background(.background)
        .ignoresSafeArea(.container, edges: .top)
        .confirmationDialog(
            "Supprimer \(count(store.selectedCount)) pour \(store.selectedTotal.formatted(.byteCount(style: .file))) ?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Supprimer \(store.selectedTotal.formatted(.byteCount(style: .file)))",
                   role: .destructive) {
                Task {
                    deleting = true
                    await store.delete()
                    deleting = false
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La suppression est immédiate et définitive : rien ne passe par la corbeille."
                 + (store.selectedShared > store.selectedTotal / 10
                    ? " Une part de ces octets est partagée par liens durs : l'espace réellement rendu sera moindre."
                    : ""))
        }
    }

    private func count(_ n: Int) -> String {
        "\(n) élément\(n > 1 ? "s" : "")"
    }

    // MARK: Barre latérale

    private var sidebar: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: bandeau - 12)

            List(selection: filterSelection) {
                Section("Catégories") {
                    ForEach(PurgeStore.Filter.allCases) { filter in
                        Label(filter.rawValue, systemImage: symbol(filter))
                            .badge(number(in: filter))
                            .tag(filter)
                            .accessibilityLabel("\(filter.rawValue), \(count(number(in: filter)))")
                    }
                }

                Section("Dossiers analysés") {
                    ForEach(store.roots, id: \.self) { root in
                        rootRow(root)
                    }
                    Button {
                        store.addRoot()
                    } label: {
                        Label("Ajouter un dossier…", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Choisir un dossier de plus à analyser")
                }

                Section("Options") {
                    Toggle("Inclure les caches globaux", isOn: $store.includeCaches)
                        .toggleStyle(.checkbox)
                        .disabled(store.scanning)
                        .help("Caches de Xcode, npm, Homebrew… situés hors des projets. Pris en compte à la prochaine analyse.")
                }
            }
            .listStyle(.sidebar)
        }
        .background(.regularMaterial)
    }

    private var filterSelection: Binding<PurgeStore.Filter?> {
        Binding(get: { store.filter }, set: { if let new = $0 { store.filter = new } })
    }

    private func symbol(_ filter: PurgeStore.Filter) -> String {
        switch filter {
        case .all:      return "tray.full"
        case .safe:     return "checkmark.shield"
        case .projects: return "hammer"
        case .caches:   return "internaldrive"
        }
    }

    private func number(in filter: PurgeStore.Filter) -> Int {
        switch filter {
        case .all:      return store.findings.count
        case .safe:     return store.findings.filter { $0.rule.impact == .none }.count
        case .projects: return store.findings.filter { !$0.isGlobal }.count
        case .caches:   return store.findings.filter(\.isGlobal).count
        }
    }

    private func rootRow(_ root: URL) -> some View {
        HStack {
            Label(label(for: root), systemImage: root == FileManager.default.homeDirectoryForCurrentUser
                  ? "house" : "folder")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Espace.xs)
            if store.roots.count > 1 {
                Button {
                    store.removeRoot(root)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Ne plus analyser ce dossier")
                .accessibilityLabel("Retirer \(label(for: root))")
            }
        }
        .help(root.path)
        .contextMenu {
            if store.roots.count > 1 {
                Button("Retirer de l'analyse") { store.removeRoot(root) }
            }
            Button("Afficher dans le Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([root])
            }
        }
    }

    /// Le dossier personnel s'appelle du nom du compte, ce qui ne veut rien
    /// dire dans une liste de dossiers. Partout ailleurs, le dernier composant
    /// suffit — c'est le nom du projet ou du volume.
    private func label(for root: URL) -> String {
        root == FileManager.default.homeDirectoryForCurrentUser
            ? "Dossier personnel"
            : root.lastPathComponent
    }

    // MARK: Colonne centrale

    private var main: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
    }

    /// Barre d'outils : le titre et l'état à gauche, les actions à droite.
    private var toolbar: some View {
        HStack(spacing: Espace.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Purge").font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Espace.s)

            if store.scanning {
                if store.progressTotal > 0 {
                    ProgressView(value: Double(store.progressDone),
                                 total: Double(store.progressTotal))
                        .frame(width: 110)
                        .accessibilityLabel("Progression de l'analyse")
                } else {
                    ProgressView().controlSize(.small)
                }
            }

            Menu {
                Button("Cocher ce qui est sans impact") { store.selectSafeOnly() }
                Button("Tout cocher") { store.selectAll(true) }
                    .keyboardShortcut("a")
                Button("Tout décocher") { store.selectAll(false) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            } label: {
                Label("Sélection", systemImage: "checklist")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(store.findings.isEmpty || deleting)
            .help("Cocher ou décocher les éléments affichés")

            if store.scanning {
                Button("Arrêter") { store.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Interrompre l'analyse (⌘.)")
            } else {
                Button(store.hasScanned ? "Analyser à nouveau" : "Analyser") { store.scan() }
                    .keyboardShortcut("r")
                    .disabled(deleting)
                    .help("Lancer l'analyse (⌘R)")
            }
        }
        .padding(.horizontal, Espace.l)
        .frame(height: bandeau)
    }

    private var subtitle: String {
        if deleting { return "Suppression en cours…" }
        if store.scanning {
            guard store.progressTotal > 0 else { return "Repérage des dossiers…" }
            return "Pesée : \(store.progressDone) sur \(store.progressTotal)"
        }
        if let report = store.report { return report }
        guard store.hasScanned else { return "Aucune analyse pour l'instant" }
        guard !store.findings.isEmpty else { return "Rien à récupérer" }
        return "\(count(store.findings.count)) · \(store.total.formatted(.byteCount(style: .file))) récupérables"
    }

    // MARK: Liste

    @ViewBuilder
    private var content: some View {
        if store.visible.isEmpty {
            emptyState
        } else {
            table
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack {
            Spacer()
            if store.scanning {
                VStack(spacing: Espace.s) {
                    ProgressView().controlSize(.large)
                    Text("Analyse en cours").font(.headline)
                    Text("Les éléments apparaissent ici dès qu'ils sont pesés.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if !store.hasScanned {
                VStack(spacing: Espace.m) {
                    EtatVide(symbole: "sparkle.magnifyingglass",
                             titre: "Prêt à analyser",
                             detail: "Purge cherche ce qui se régénère tout seul et dit ce que chaque suppression coûte, avant que tu ne coches quoi que ce soit.")
                    Button("Analyser") { store.scan() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .frame(maxWidth: 380)
            } else if store.findings.isEmpty {
                EtatVide(symbole: "checkmark.circle",
                         titre: "Rien à récupérer",
                         detail: "Le disque est déjà propre.")
                    .frame(maxWidth: 380)
            } else {
                EtatVide(symbole: "tray",
                         titre: "Rien dans cette catégorie",
                         detail: "Choisis une autre catégorie dans la barre latérale.")
                    .frame(maxWidth: 380)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Espace.l)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
    }

    private var table: some View {
        Table(store.visible, selection: focusBinding) {
            TableColumn("") { finding in
                Toggle("", isOn: Binding(
                    get: { store.selection.contains(finding.id) },
                    set: { _ in store.toggle(finding) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(deleting)
                .accessibilityLabel("Cocher \(finding.project), \(finding.rule.directory)")
            }
            .width(24)

            TableColumn("Élément") { finding in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Espace.s) {
                        Text(finding.project)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(finding.rule.directory)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(line(finding))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .help(finding.url.path)
            }

            TableColumn("Impact") { finding in
                impactLabel(finding.rule.impact)
            }
            .width(min: 100, ideal: 112, max: 140)

            TableColumn("Taille") { finding in
                Text(finding.size.formatted(.byteCount(style: .file)))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Taille \(finding.size.formatted(.byteCount(style: .file)))")
            }
            .width(min: 72, ideal: 84, max: 110)
        }
        .tableStyle(.inset)
        // Espace : coche ou décoche la ligne sélectionnée, comme dans Mail.
        .onKeyPress(.space) {
            guard !deleting, let focus = store.focus else { return .ignored }
            store.toggle(focus)
            return .handled
        }
        // Touche Supprimer : ouvre la confirmation, jamais de suppression directe.
        .onDeleteCommand {
            if store.selectedCount > 0, !store.scanning, !deleting {
                confirming = true
            } else {
                NSSound.beep()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
    }

    private var focusBinding: Binding<String?> {
        Binding(
            get: { store.focus?.id },
            set: { id in store.focus = store.findings.first { $0.id == id } }
        )
    }

    private func line(_ finding: Finding) -> String {
        var parts = ["\(finding.files.formatted()) fichiers"]
        if let modified = finding.modified {
            parts.append("modifié \(modified.formatted(.relative(presentation: .numeric)))")
        }
        // Seulement quand la part partagée est significative : la signaler pour
        // trois fichiers sur mille n'apprendrait rien.
        if finding.shared > finding.size / 5 {
            parts.append("\(finding.shared.formatted(.byteCount(style: .file))) en liens durs")
        }
        return parts.joined(separator: " · ")
    }

    /// Le symbole double la couleur : l'impact se lit aussi sans la voir.
    private func impactLabel(_ impact: Impact) -> some View {
        Label(impact.label, systemImage: impactSymbol(impact))
            .font(.callout)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.palette)
            .labelStyle(ImpactLabelStyle(teinte: color(impact)))
            .lineLimit(1)
    }

    private func impactSymbol(_ impact: Impact) -> String {
        switch impact.severity {
        case 1:  return "checkmark.circle.fill"
        case 2:  return "arrow.triangle.2.circlepath.circle.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private func color(_ impact: Impact) -> Color {
        switch impact.severity {
        case 1:  return .green
        case 2:  return .yellow
        default: return .orange
        }
    }

    // MARK: Barre d'action flottante

    /// Posée sur la liste, qui défile dessous : c'est la couche des contrôles,
    /// donc la seule à recevoir du verre. Le bouton de suppression est rouge,
    /// jamais l'action par défaut, et toute la décision tient ici : combien,
    /// pour quel volume, avec quelle réserve.
    private var actionBar: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            if !store.failures.isEmpty {
                Label(store.failures.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: Espace.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectionSummary)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    Text(barDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                }
                Spacer(minLength: Espace.s)

                if deleting {
                    ProgressView().controlSize(.small)
                }

                Button(role: .destructive) {
                    confirming = true
                } label: {
                    Text("Supprimer…")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(store.selectedCount == 0 || store.scanning || deleting)
                .help(store.scanning
                      ? "Attends la fin de l'analyse"
                      : "Supprimer les éléments cochés (touche Supprimer)")
            }
        }
        .padding(.horizontal, Espace.l)
        .padding(.vertical, Espace.m)
        .verre(.rect(cornerRadius: 16))
        .padding(Espace.m)
    }

    private var selectionSummary: String {
        guard store.selectedCount > 0 else { return "Aucun élément coché" }
        return "\(count(store.selectedCount)) coché\(store.selectedCount > 1 ? "s" : "") · "
            + store.selectedTotal.formatted(.byteCount(style: .file))
    }

    private var barDetail: String {
        if store.selectedShared > store.selectedTotal / 10 {
            return "Dont \(store.selectedShared.formatted(.byteCount(style: .file))) partagés par liens durs : l'espace rendu sera moindre si l'autre copie reste."
        }
        if let volume = store.volumes.first {
            return "\(volume.name) · \(volume.free.formatted(.byteCount(style: .file))) libres"
        }
        return "Suppression immédiate et définitive"
    }

    // MARK: Inspecteur

    @ViewBuilder
    private var inspector: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: bandeau - 12)
            if let finding = store.focus {
                ScrollView {
                    VStack(alignment: .leading, spacing: Espace.l) {
                        VStack(alignment: .leading, spacing: Espace.xs) {
                            Text(finding.rule.directory)
                                .font(.title3.monospaced())
                                .textSelection(.enabled)
                            Text(finding.project)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            impactLabel(finding.rule.impact)
                                .padding(.top, 2)
                        }
                        .accessibilityElement(children: .combine)

                        section("Ce que c'est", finding.rule.what)
                        section("Ce que ça casse", finding.rule.breaks)
                        section("Comment ça revient", finding.rule.recovery)

                        if let command = finding.command {
                            commandBox(command)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: Espace.s) {
                            Ligne("Taille", finding.size.formatted(.byteCount(style: .file)))
                            Ligne("Fichiers", finding.files.formatted())
                            if finding.shared > 0 {
                                Ligne("Dont partagés", finding.shared.formatted(.byteCount(style: .file)))
                            }
                            if let modified = finding.modified {
                                Ligne("Dernière écriture",
                                      modified.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .font(.subheadline)

                        if finding.shared > finding.size / 5 {
                            Label("Une grande partie de ce dossier est partagée par liens durs avec d'autres dossiers — typiquement le magasin pnpm et les node_modules des projets. Ces octets ne sont rendus au disque que lorsque la dernière copie disparaît : supprimer un seul des deux côtés ne libère presque rien.",
                                  systemImage: "link")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(finding.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([finding.url])
                        } label: {
                            Label("Afficher dans le Finder", systemImage: "folder")
                        }
                        .controlSize(.small)
                        .help("Afficher le dossier dans le Finder")
                    }
                    .padding(Espace.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
                EtatVide(symbole: "info.circle",
                         titre: "Aucune sélection",
                         detail: "Choisis une ligne pour savoir ce qu'elle contient, ce que sa suppression casse, et comment ça revient.")
                    .padding(.horizontal, Espace.l)
                Spacer()
            }
        }
        .background(.background.secondary)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func commandBox(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            Text("Commande")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(command)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Espace.xs)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copier la commande")
                .accessibilityLabel("Copier la commande")
            }
            .padding(Espace.s)
            .surface()
        }
    }
}

/// Symbole teinté, texte sobre : la couleur porte le sens, pas le texte.
private struct ImpactLabelStyle: LabelStyle {
    let teinte: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(teinte)
            configuration.title
        }
    }
}
