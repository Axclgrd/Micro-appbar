import Commun
import SwiftUI

/// Le panneau d'une icône : la liste des outils du groupe, puis l'outil choisi.
///
/// Pas de verre ici. Le popover du système en pose déjà, et Apple est explicite :
/// le verre ne se superpose pas au verre.
struct GroupPanel: View {
    let group: MenuGroup
    @State private var opened: String?

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
        .padding(.vertical, 10)
        .animation(.snappy(duration: 0.2), value: opened)
    }

    // MARK: La liste

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.displayName)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            if modules.isEmpty {
                Text("Ce groupe est vide. Ajoute-lui des outils dans les réglages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            ForEach(modules, id: \.id) { module in
                Button {
                    opened = module.id
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: module.symbol)
                            .font(.system(size: 13))
                            .frame(width: 18)
                            .foregroundStyle(.tint)
                        Text(module.title)
                            .font(.callout)
                        Spacer(minLength: 6)
                        Text(module.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 8)

            HStack(spacing: 0) {
                Button("Réglages de la trousse…") { Dashboard.shared.show() }
                    .buttonStyle(.plain)
                    .font(.caption)
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
        }
    }

    // MARK: Un outil

    private func detail(_ module: Module) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    opened = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text(module.title)
                    .font(.callout.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)

            module.makePanel()
        }
    }
}
