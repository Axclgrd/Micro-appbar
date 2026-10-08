import Commun
import SwiftUI

public struct ContentView: View {
    @Bindable var store: PurgeStore

    public init(store: PurgeStore) { self.store = store }
    @State private var confirming = false

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                list
                Divider()
                detail.frame(width: 290)
            }
            Divider()
            footer
        }
        .frame(minWidth: 880, minHeight: 560)
        .background(.background)
        .confirmationDialog(
            "Supprimer \(store.selectedCount) élément\(store.selectedCount > 1 ? "s" : "") ?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Supprimer définitivement", role: .destructive) {
                Task { await store.delete() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("\(store.selectedTotal.formatted(.byteCount(style: .file))) seront libérés. La suppression est immédiate et définitive : rien ne passe par la corbeille.")
        }
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Purge").font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if store.scanning {
                    if store.progressTotal > 0 {
                        ProgressView(value: Double(store.progressDone),
                                     total: Double(store.progressTotal))
                            .frame(width: 120)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Button("Arrêter") { store.cancel() }
                } else {
                    Button("Analyser") { store.scan() }
                        .keyboardShortcut(.defaultAction)
                }
            }

            HStack(spacing: 6) {
                ForEach(store.roots, id: \.self) { root in
                    chip(root)
                }
                Button {
                    store.addRoot()
                } label: {
                    Label("Ajouter", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                Toggle("Caches globaux", isOn: $store.includeCaches)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Le bandeau du haut est masqué : on rend sa place aux pastilles de
        // fenêtre plutôt que d'afficher un titre en double.
        .padding(.top, 30)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        if store.scanning {
            guard store.progressTotal > 0 else { return "Repérage des dossiers…" }
            return "Pesée : \(store.progressDone) / \(store.progressTotal)"
        }
        if let report = store.report { return report }
        guard store.hasScanned else {
            return "Cherche ce qui se régénère tout seul, et dit ce que chaque suppression coûte."
        }
        guard !store.findings.isEmpty else { return "Rien à récupérer. Le disque est déjà propre." }
        return "\(store.findings.count) éléments · \(store.total.formatted(.byteCount(style: .file))) récupérables"
    }

    private func chip(_ root: URL) -> some View {
        HStack(spacing: 4) {
            Text(label(for: root)).font(.caption)
            if store.roots.count > 1 {
                Button {
                    store.removeRoot(root)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .help(root.path)
    }

    /// Le dossier personnel s'appelle du nom du compte, ce qui ne veut rien
    /// dire dans une liste de dossiers. Partout ailleurs, le dernier composant
    /// suffit — c'est le nom du projet ou du volume.
    private func label(for root: URL) -> String {
        root == FileManager.default.homeDirectoryForCurrentUser
            ? "Dossier personnel"
            : root.lastPathComponent
    }

    // MARK: Liste

    private var list: some View {
        Group {
            if store.visible.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: store.hasScanned ? "checkmark.circle" : "sparkle.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(store.hasScanned
                         ? "Rien dans cette catégorie."
                         : "Lance une analyse pour voir ce qui dort sur le disque.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(store.visible, id: \.id, selection: focusBinding) { finding in
                    row(finding)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var focusBinding: Binding<String?> {
        Binding(
            get: { store.focus?.id },
            set: { id in store.focus = store.findings.first { $0.id == id } }
        )
    }

    private func row(_ finding: Finding) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { store.selection.contains(finding.id) },
                set: { _ in store.toggle(finding) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(finding.project)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(finding.rule.directory)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(line(finding))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(finding.size.formatted(.byteCount(style: .file)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            pill(finding.rule.impact).frame(width: 104, alignment: .trailing)
        }
        .padding(.vertical, 3)
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

    private func pill(_ impact: Impact) -> some View {
        Text(impact.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color(impact).opacity(0.16), in: Capsule())
            .foregroundStyle(color(impact))
    }

    private func color(_ impact: Impact) -> Color {
        switch impact.severity {
        case 1:  return .green
        case 2:  return .yellow
        default: return .orange
        }
    }

    // MARK: Détail

    @ViewBuilder
    private var detail: some View {
        if let finding = store.focus {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(finding.rule.directory)
                            .font(.title3.monospaced())
                        Text(finding.project)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        pill(finding.rule.impact)
                    }

                    section("Ce que c'est", finding.rule.what)
                    section("Ce que ça casse", finding.rule.breaks)
                    section("Comment ça revient", finding.rule.recovery)

                    if let command = finding.command {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Commande").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            HStack {
                                Text(command)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(command, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        fact("Taille", finding.size.formatted(.byteCount(style: .file)))
                        fact("Fichiers", finding.files.formatted())
                        if finding.shared > 0 {
                            fact("Dont partagés", finding.shared.formatted(.byteCount(style: .file)))
                        }
                        if let modified = finding.modified {
                            fact("Dernière écriture", modified.formatted(date: .abbreviated, time: .shortened))
                        }
                    }

                    if finding.shared > finding.size / 5 {
                        Text("Une grande partie de ce dossier est partagée par liens durs avec d'autres dossiers — typiquement le magasin pnpm et les node_modules des projets. Ces octets ne sont rendus au disque que lorsque la dernière copie disparaît : supprimer un seul des deux côtés ne libère presque rien.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(finding.url.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([finding.url])
                    } label: {
                        Label("Révéler dans le Finder", systemImage: "folder")
                    }
                    .controlSize(.small)

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "questionmark.folder")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                Text("Sélectionne une ligne pour savoir ce qu'elle contient, ce que sa suppression casse, et comment ça revient.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(20)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(body).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    // MARK: Pied

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Picker("", selection: $store.filter) {
                    ForEach(PurgeStore.Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Menu("Sélection") {
                    Button("Cocher ce qui est sans impact") { store.selectSafeOnly() }
                    Button("Tout cocher (\(store.visible.count) affichés)") { store.selectAll(true) }
                    Button("Tout décocher") { store.selectAll(false) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(store.findings.isEmpty)

                if store.selectedCount > 0 {
                    Text("\(store.selectedCount) coché\(store.selectedCount > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ForEach(store.volumes, id: \.name) { volume in
                    Text("\(volume.name) · \(volume.free.formatted(.byteCount(style: .file))) libres")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    confirming = true
                } label: {
                    Text(store.selectedCount == 0
                         ? "Supprimer"
                         : "Supprimer \(store.selectedTotal.formatted(.byteCount(style: .file)))")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(store.selectedCount == 0 || store.scanning)
            }

            if store.selectedShared > store.selectedTotal / 10 {
                Text("Dont \(store.selectedShared.formatted(.byteCount(style: .file))) partagés par liens durs : l'espace réellement rendu sera moindre si l'autre copie reste en place.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !store.failures.isEmpty {
                Text(store.failures.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
