import Commun
import SwiftUI

@MainActor
public final class EjecterModule: Module {
    private let store = DiskStore()

    public init() {}

    public let id = "ejecter"
    public let title = "Éjecter"

    public var symbol: String {
        store.devices.contains(where: \.isMounted) ? "eject.fill" : "eject"
    }

    /// Aucun disque externe, aucune image montée : rien à dire, donc pas
    /// d'icône. C'était déjà le parti pris de l'app autonome.
    public var isRelevant: Bool {
        !store.devices.isEmpty || store.alwaysVisible
    }

    public var summary: String {
        let mounted = store.devices.filter(\.isMounted).count
        guard mounted > 0 else { return store.devices.isEmpty ? "" : "aucun monté" }
        return "\(mounted) monté\(mounted > 1 ? "s" : "")"
    }

    public func makePanel() -> AnyView {
        AnyView(PanelView(store: store))
    }
}
