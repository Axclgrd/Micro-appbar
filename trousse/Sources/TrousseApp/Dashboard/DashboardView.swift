import Commun
import SwiftUI

/// La composition de la barre du haut.
///
/// Une fenêtre à la manière de Réglages Système : à gauche les groupes (une
/// icône de la barre chacun) et, à part, les outils masqués ; à droite le
/// détail du groupe choisi, en formulaire groupé.
///
/// Le verre vient de la barre latérale et de la barre d'outils du système, qui
/// le posent d'eux-mêmes sur la couche des contrôles. Le contenu reste sur les
/// surfaces standard des listes et formulaires : aucun verre n'est dessiné ici,
/// donc ni verre sur verre ni verre sur le contenu.
struct DashboardView: View {
    @State private var config = Config.shared
    @State private var selection: Destination?

    enum Destination: Hashable {
        case group(UUID)
        case hidden
    }

    /// Une sélection devenue invalide (groupe supprimé) retombe sur le premier
    /// groupe, plutôt que de laisser un détail vide.
    private var current: Destination? {
        switch selection {
        case .group(let id) where config.groups.contains(where: { $0.id == id }): return selection
        case .hidden: return selection
        default: return config.groups.first.map { .group($0.id) }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 640, minHeight: 440)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selection = .group(config.addGroup())
                } label: {
                    Label("Nouveau groupe", systemImage: "plus")
                }
                .keyboardShortcut("n")
                .help("Ajouter un groupe à la barre des menus (⌘N)")
            }
        }
    }

    // MARK: La barre latérale

    private var sidebar: some View {
        List(selection: Binding(get: { current }, set: { selection = $0 })) {
            Section("Barre des menus") {
                ForEach(config.groups) { group in
                    Label(group.displayName, systemImage: group.symbol)
                        .tag(Destination.group(group.id))
                        .contextMenu {
                            Button("Supprimer le groupe", role: .destructive) {
                                config.removeGroup(group)
                            }
                        }
                }
                .onMove { config.moveGroups(from: $0, to: $1) }
            }
            Section("Hors de la barre") {
                Label("Masqués", systemImage: "eye.slash")
                    .badge(config.hidden.count)
                    .tag(Destination.hidden)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Le détail

    @ViewBuilder
    private var detail: some View {
        switch current {
        case .group(let id):
            if let group = config.groups.first(where: { $0.id == id }) {
                GroupDetail(group: group)
                    .id(group.id)
            }
        case .hidden:
            HiddenDetail()
        case nil:
            ContentUnavailableView {
                Label("Aucun groupe", systemImage: "menubar.rectangle")
            } description: {
                Text("Un groupe est une icône de la barre des menus. Crée-en un pour y ranger des outils.")
            } actions: {
                Button("Nouveau groupe") { selection = .group(config.addGroup()) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Un groupe

/// Le détail d'un groupe : son identité, puis ses outils.
struct GroupDetail: View {
    let group: MenuGroup
    private var config: Config { Config.shared }

    /// Assez de symboles pour distinguer des groupes, pas assez pour hésiter.
    private static let symbols: [(name: String, label: String)] = [
        ("square.grid.2x2", "Grille"), ("shippingbox", "Boîte"),
        ("wrench.and.screwdriver", "Outils"), ("gauge.with.dots.needle.33percent", "Jauge"),
        ("externaldrive", "Disque"), ("moon", "Lune"),
        ("text.viewfinder", "Texte"), ("waveform", "Onde"),
        ("app.connected.to.app.below.fill", "Connexions"), ("bolt", "Éclair"),
        ("thermometer.medium", "Thermomètre"), ("folder", "Dossier"),
    ]

    /// Les outils qui ne sont pas déjà dans ce groupe : ceux qu'on peut y amener.
    private var available: [Module] {
        Registry.shared.modules.filter { !group.modules.contains($0.id) }
    }

    var body: some View {
        let modules = config.modules(of: group)
        Form {
            Section {
                TextField("Nom", text: Binding(
                    get: { group.name },
                    set: { config.rename(group, to: $0) }),
                    prompt: Text("Nom du groupe"))
                    .help("Le nom du groupe, affiché dans le panneau et en infobulle")

                Picker("Icône", selection: Binding(
                    get: { group.symbol },
                    set: { config.setSymbol($0, for: group) })) {
                    ForEach(Self.symbols, id: \.name) { symbol in
                        Label(symbol.label, systemImage: symbol.name).tag(symbol.name)
                    }
                }
                .help("L'icône du groupe dans la barre des menus")
            } header: {
                Text("Groupe")
            } footer: {
                Text("Le panneau de la barre des menus montre les outils de ce groupe, dans cet ordre.")
            }

            Section("Outils") {
                if modules.isEmpty {
                    Text("Aucun outil. Cette icône n'ouvrirait qu'un panneau vide.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(modules, id: \.id) { module in
                        ToolRow(module: module, current: group)
                    }
                    .onMove { config.moveModules(in: group, from: $0, to: $1) }
                }

                Menu {
                    ForEach(available, id: \.id) { module in
                        Button {
                            config.place(module.id, in: group)
                        } label: {
                            Label(module.title, systemImage: module.symbol)
                        }
                    }
                } label: {
                    Label("Ajouter un outil", systemImage: "plus.circle")
                }
                .menuIndicator(.hidden)
                .disabled(available.isEmpty)
                .help("Ajouter un outil à ce groupe")
            }

            Section {
                Button("Supprimer le groupe", role: .destructive) {
                    config.removeGroup(group)
                }
            } footer: {
                Text("Les outils du groupe passent dans les masqués.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(group.displayName)
    }
}

// MARK: - Les masqués

/// Les outils qu'on ne veut voir dans aucun groupe.
struct HiddenDetail: View {
    @State private var config = Config.shared

    var body: some View {
        let modules = Registry.shared.modules.filter { config.hidden.contains($0.id) }
        Group {
            if modules.isEmpty {
                ContentUnavailableView {
                    Label("Aucun outil masqué", systemImage: "eye")
                } description: {
                    Text("Un outil masqué reste utilisable — par son raccourci, ou depuis cette fenêtre — mais ne prend pas de place dans la barre.")
                }
            } else {
                Form {
                    Section {
                        ForEach(modules, id: \.id) { module in
                            ToolRow(module: module, current: nil)
                        }
                    } footer: {
                        Text("Un outil masqué reste utilisable par son raccourci, mais ne prend pas de place dans la barre.")
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Masqués")
    }
}

// MARK: - Un outil

/// Une ligne d'outil : son symbole, son nom, son état, et où l'envoyer.
///
/// Le groupe courant porte la coche dans le menu ouvert, là où il s'agit
/// justement de choisir une destination.
struct ToolRow: View {
    let module: Module
    let current: MenuGroup?
    private var config: Config { Config.shared }

    var body: some View {
        HStack(spacing: Espace.m) {
            Image(systemName: module.symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(module.title)
                if !module.summary.isEmpty {
                    Text(module.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Espace.s)

            Menu {
                Section("Déplacer vers") {
                    ForEach(config.groups) { destination in
                        Button {
                            config.place(module.id, in: destination)
                        } label: {
                            if current?.id == destination.id {
                                Label(destination.displayName, systemImage: "checkmark")
                            } else {
                                Text(destination.displayName)
                            }
                        }
                    }
                }
                if current != nil {
                    Divider()
                    Button("Masquer", systemImage: "eye.slash") {
                        config.place(module.id, in: nil)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Déplacer vers un autre groupe, ou masquer")
            .accessibilityLabel("Actions pour \(module.title)")
        }
        .accessibilityElement(children: .contain)
    }
}
