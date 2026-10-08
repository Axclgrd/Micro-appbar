import AppKit
import Commun
import SwiftUI

@MainActor
public final class PurgeModule: Module {
    private let store = PurgeStore()
    private lazy var window = ToolWindow(
        title: "Purge",
        size: NSSize(width: 980, height: 640)) { [store] in AnyView(ContentView(store: store)) }

    public init() {}

    public let id = "purge"
    public let title = "Purge"
    public let symbol = "arrow.down.circle"

    public var summary: String { store.headline }

    public let hasWindow = true

    /// L'app installée d'abord : c'est elle qui porte l'icône du Dock et la
    /// dernière version. La fenêtre interne ne sert que si elle manque.
    public func open() {
        guard !ExternalApp.open("local.purge") else { return }
        window.show()
    }

    public func makePanel() -> AnyView {
        AnyView(WindowToolPanel(
            explanation: "Cherche les artefacts de build qui se régénèrent, et dit ce que chaque suppression coûte.",
            state: summary,
            action: "Ouvrir Purge") { [weak self] in self?.open() })
    }
}

/// Le panneau d'un outil à fenêtre : ce qu'il fait, où il en est, et le bouton
/// qui ouvre la vraie interface. Une liste de suppressions à cocher dans un
/// popover qui se referme au moindre clic ailleurs serait un piège.
struct WindowToolPanel: View {
    let explanation: String
    let state: String
    let action: String
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !state.isEmpty {
                Text(state)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            // Le seul geste du panneau : il ouvre la fenêtre, il ne supprime rien.
            Button(action, action: open)
                .controlSize(.small)
                .help("Ouvre la fenêtre de Purge")
        }
        .padding(.horizontal, Espace.panneau)
    }
}
