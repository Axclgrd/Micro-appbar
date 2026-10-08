import Commun
import SwiftUI

/// Le panneau d'une icône : la liste des outils du groupe, puis l'outil choisi.
///
/// Pas de verre ici. Le popover du système en pose déjà, et Apple est explicite :
/// le verre ne se superpose pas au verre. Le contenu reste sur le fond du
/// popover ; seul le survol d'une ligne dessine une surface douce (`survol`).
struct GroupPanel: View {
    let group: MenuGroup
    @State private var opened: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(group: MenuGroup, initial: String? = nil) {
        self.group = group
        _opened = State(initialValue: initial)
    }

    private var modules: [Module] { Config.shared.modules(of: group) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let opened, let module = Registry.shared.module(opened) {
                detail(module)
            } else {
                list
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: opened)
    }

    // MARK: La liste

    private var list: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Label(group.displayName, systemImage: group.symbol)
                .font(.headline)
                .padding(.horizontal, Espace.panneau)

            if modules.isEmpty {
                EtatVide(symbole: "tray", titre: "Groupe vide",
                         detail: "Ajoute-lui des outils dans les réglages de Trousse.")
                    .padding(.horizontal, Espace.panneau)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(modules, id: \.id) { module in
                        row(module)
                    }
                }
                .padding(.horizontal, Espace.s)
            }

            PiedDePanneau {
                Button("Réglages…") { Dashboard.shared.show() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Composer les groupes et les outils")
            }
            .padding(.horizontal, Espace.panneau)
        }
        .padding(.vertical, Espace.panneau)
    }

    private func row(_ module: Module) -> some View {
        Button {
            opened = module.id
        } label: {
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
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Espace.s)
            .padding(.vertical, Espace.s)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .survol()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre l'outil")
        .help(module.title)
    }

    // MARK: Un outil

    private func detail(_ module: Module) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack(spacing: Espace.s) {
                Button {
                    opened = nil
                } label: {
                    Label(group.displayName, systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Revenir à la liste des outils")

                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal, Espace.panneau)

            Text(module.title)
                .font(.headline)
                .padding(.horizontal, Espace.panneau)

            module.makePanel()
        }
        .padding(.vertical, Espace.m)
    }
}
