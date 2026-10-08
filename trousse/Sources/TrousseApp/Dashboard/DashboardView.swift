import Commun
import SwiftUI

/// La composition de la barre du haut.
///
/// Le verre suit la règle d'Apple : il n'habille que ce qui flotte au-dessus du
/// contenu — ici la barre d'actions du bas. Les cartes de groupes sont du
/// contenu, elles restent en matériau opaque. Verre sur verre est proscrit, et
/// une seule chose est teintée : l'action principale.
struct DashboardView: View {
    @State private var config = Config.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView { DashboardContent() }
            actions
        }
        .frame(minWidth: 560, minHeight: 460)
        .background(.background)
    }

    // MARK: La barre flottante

    private var actions: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    Config.shared.addGroup()
                } label: {
                    Label("Nouveau groupe", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)

                Button {
                    NSApp.keyWindow?.performClose(nil)
                } label: {
                    Text("Fermer")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.bottom, 18)
    }
}

/// Le contenu, séparé de la fenêtre qui le fait défiler — ce qui permet aussi
/// de le rendre hors écran pour le relire.
struct DashboardContent: View {
    @State private var config = Config.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ForEach(config.groups) { group in
                GroupCard(group: group)
            }
            hidden
            Color.clear.frame(height: 64)   // la place de la barre flottante
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Trousse").font(.title2.weight(.semibold))
            Text("Ce qui apparaît dans la barre du haut, et sous quel nom.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    // MARK: Les masqués

    @ViewBuilder
    private var hidden: some View {
        let modules = Registry.shared.modules.filter { config.hidden.contains($0.id) }
        VStack(alignment: .leading, spacing: 8) {
            Text("Masqués")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if modules.isEmpty {
                Text("Aucun. Un outil masqué reste utilisable — par son raccourci, ou depuis cette fenêtre — mais ne prend pas de place dans la barre.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(modules, id: \.id) { module in
                    ModuleRow(module: module)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

}

/// Un groupe : une icône de la barre, son nom, et ce qu'il contient.
struct GroupCard: View {
    let group: MenuGroup
    private var config: Config { Config.shared }

    @FocusState private var editing: Bool
    @State private var hovering = false

    /// Assez de symboles pour distinguer des groupes, pas assez pour hésiter.
    private static let symbols = [
        "square.grid.2x2", "shippingbox", "wrench.and.screwdriver", "gauge.with.dots.needle.33percent",
        "externaldrive", "moon", "text.viewfinder", "waveform",
        "app.connected.to.app.below.fill", "bolt", "thermometer.medium", "folder",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            config.setSymbol(symbol, for: group)
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                } label: {
                    Image(systemName: group.symbol)
                        .font(.system(size: 14))
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Changer l'icône du groupe")

                // Au repos c'est le titre de la carte, pas une boîte grise posée
                // en plein milieu. Le fond n'apparaît qu'au survol — et le
                // curseur en I du champ texte le confirme avant même le clic —
                // puis franchement pendant la saisie, où il faut voir jusqu'où
                // le nom peut aller.
                TextField("Nom du groupe", text: Binding(
                    get: { group.name },
                    set: { config.rename(group, to: $0) }))
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($editing)
                    .frame(maxWidth: 240, alignment: .leading)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.quaternary)
                            .opacity(editing ? 0.7 : (hovering ? 0.35 : 0))
                    }
                    .onHover { hovering = $0 }
                    .animation(.easeOut(duration: 0.12), value: hovering)
                    .animation(.easeOut(duration: 0.12), value: editing)
                    .help("Renommer le groupe")

                Spacer(minLength: 4)

                Menu {
                    Button("Monter") { config.move(group, by: -1) }
                    Button("Descendre") { config.move(group, by: 1) }
                    Divider()
                    Button("Supprimer le groupe", role: .destructive) { config.removeGroup(group) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            let modules = config.modules(of: group)
            if modules.isEmpty {
                Text("Vide — cette icône n'ouvrirait qu'un panneau blanc.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(modules, id: \.id) { module in
                    ModuleRow(module: module)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}

/// Une ligne d'outil, et où l'envoyer.
///
/// Le menu ne porte plus le nom du groupe courant : répété sur chaque ligne
/// d'une carte, il redisait ce que la carte annonce déjà en titre. Le groupe
/// courant reste lisible là où il sert vraiment — la coche, dans le menu
/// ouvert, quand il s'agit justement de choisir une destination.
struct ModuleRow: View {
    let module: Module
    private var config: Config { Config.shared }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: module.symbol)
                .font(.system(size: 13))
                .frame(width: 20)
                .foregroundStyle(.tint)

            Text(module.title).font(.callout)

            Spacer(minLength: 8)

            Menu {
                ForEach(config.groups) { destination in
                    Button {
                        config.place(module.id, in: destination)
                    } label: {
                        if config.group(containing: module.id)?.id == destination.id {
                            Label(destination.displayName, systemImage: "checkmark")
                        } else {
                            Text(destination.displayName)
                        }
                    }
                }
                Divider()
                Button("Masquer") { config.place(module.id, in: nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 18)
                    .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Déplacer vers un autre groupe, ou masquer")
        }
        .padding(.vertical, 3)
    }
}
