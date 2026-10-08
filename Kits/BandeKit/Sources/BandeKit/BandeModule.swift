import AppKit
import Commun
import SwiftUI

@MainActor
public final class BandeModule: Module {
    private let store = BandeStore.shared
    private lazy var window = ToolWindow(
        title: "Bande",
        size: NSSize(width: 560, height: 470)) { AnyView(ContentView(store: BandeStore.shared)) }

    public init() {}

    public let id = "bande"
    public let title = "Bande"
    public let symbol = "waveform"

    public var summary: String { store.summary }

    public let hasWindow = true

    /// L'app installée d'abord : c'est elle qui porte l'icône du Dock et la
    /// dernière version. La fenêtre interne ne sert que si elle manque.
    public func open() {
        guard !ExternalApp.open("local.bande") else { return }
        window.show()
    }

    public func makePanel() -> AnyView {
        AnyView(WindowToolPanel(
            explanation: "Dépose une vidéo dans la fenêtre : son audio sort à côté du fichier d'origine.",
            state: store.summary,
            action: "Ouvrir Bande") { [weak self] in self?.open() })
    }
}

/// Le panneau d'un outil à fenêtre : ce qu'il fait, où il en est, et le bouton
/// qui ouvre la vraie interface. Un glisser-déposer dans un popover qui se
/// referme au moindre clic ailleurs serait un piège.
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button(action, action: open)
                .controlSize(.small)
                .help("Ouvre la fenêtre de Bande")
        }
        .padding(.horizontal, 14)
    }
}
