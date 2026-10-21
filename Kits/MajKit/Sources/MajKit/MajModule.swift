import Commun
import SwiftUI

/// Met la suite à jour depuis GitHub : désactivé par défaut, puis « Prévenir »
/// ou « Automatique ». Le réglage vit dans ce panneau (Shared.defaults).
@MainActor
public final class MajModule: Module {
    private let maj = Maj()

    public init() {}

    public let id = "maj"
    public let title = "Mise à jour"

    public var symbol: String {
        if maj.installation { return "arrow.triangle.2.circlepath.circle.fill" }
        if let a = maj.apercu, a.blocage == nil { return "arrow.down.circle.fill" }
        return "arrow.triangle.2.circlepath"
    }

    public var summary: String { maj.resume }

    public func activate() {
        Task { await maj.actualiserNotifications() }
    }

    public func makePanel() -> AnyView {
        AnyView(MajPanel(maj: maj))
    }
}
