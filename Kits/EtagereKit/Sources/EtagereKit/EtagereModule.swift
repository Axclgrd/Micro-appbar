import AppKit
import Commun
import SwiftUI

@MainActor
public final class EtagereModule: Module {
    private let shelf = Shelf.shared
    private var controller: ShelfController?

    public init() {
        // Deux étagères sous la même encoche se disputeraient la place et
        // garderaient chacune sa propre liste. L'app autonome s'efface donc
        // devant la trousse ici aussi, sans attendre que sa coquille de barre
        // de menus le fasse : la tablette, elle, se poserait avant.
        guard Bundle.main.bundleIdentifier == Shared.trousseIdentifier
                || !Presence.shared.trousseIsRunning else { return }
        let controller = ShelfController(shelf: shelf)
        controller.start()
        self.controller = controller
    }

    public let id = "etagere"
    public let title = "Étagère"

    public var symbol: String {
        shelf.items.isEmpty ? "tray" : "tray.full"
    }

    public var summary: String {
        guard !shelf.items.isEmpty else { return "" }
        let missing = shelf.items.filter(\.missing).count
        let base = "\(shelf.items.count) objet\(shelf.items.count > 1 ? "s" : "")"
        return missing > 0 ? "\(base), \(missing) introuvable\(missing > 1 ? "s" : "")" : base
    }

    /// Le nombre d'objets à côté de l'icône. C'est la même information que le
    /// renflement sous l'encoche, pour qui garde l'icône sous les yeux.
    public var badge: String? {
        shelf.items.isEmpty ? nil : "\(shelf.items.count)"
    }

    /// Fait sortir la tablette quelques secondes, pour montrer où elle est.
    public func reveal() {
        controller?.reveal()
    }

    public func makePanel() -> AnyView {
        AnyView(EtagerePanel(shelf: shelf, reveal: { [weak self] in self?.reveal() }))
    }
}
