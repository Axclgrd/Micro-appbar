import AppKit
import Commun
import SwiftUI

@MainActor
public final class FonteModule: Module {
    private let store = FonteStore.shared
    private lazy var window = ToolWindow(
        title: "Fonte",
        size: NSSize(width: 1040, height: 660)) { AnyView(ContentView(store: FonteStore.shared)) }

    public init() {
        // Une capture aboutie ouvre la fenêtre : c'est là que la réponse
        // arrive, et un popover refermé au premier clic ne la montrerait pas.
        store.present = { [weak self] in self?.open() }
    }

    public let id = "fonte"
    public let title = "Fonte"

    public var symbol: String {
        store.capturing || store.analyzingCount > 0 ? "character.magnify" : "textformat"
    }

    /// Comme Grab : le raccourci suffit, l'icône est facultative.
    public var isRelevant: Bool { store.showIcon }

    public var summary: String {
        if store.capturing { return "capture…" }
        if store.analyzingCount > 0 { return "analyse…" }
        guard let best = store.latest?.verdict?.best else { return "" }
        return "\(best.family) · \(best.confidence) %"
    }

    /// Le panneau reste l'entrée — capturer se fait d'un clic. La fenêtre,
    /// elle, s'ouvre sur un résultat ou à la demande.
    public func open() {
        window.show()
    }

    /// Rend l'icône après qu'on l'a masquée : le geste « relancer l'app ».
    public func revealIcon() {
        store.showIcon = true
    }

    public func activate() {
        store.refreshPermission()
        store.refreshClaude()
        // Ouvrir le panneau, c'est vouloir s'en servir : le bon moment pour
        // que macOS pose sa question, et que l'app existe dans les Réglages.
        store.askQuietly()
    }

    public func makePanel() -> AnyView {
        AnyView(PanelView(store: store) { [weak self] in self?.open() })
    }
}
