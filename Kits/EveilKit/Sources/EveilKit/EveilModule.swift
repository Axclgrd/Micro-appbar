import Commun
import SwiftUI

@MainActor
public final class EveilModule: Module {
    /// Un seul objet `Awake` par processus : deux assertions d'énergie pour la
    /// même intention, ce serait une machine qui reste éveillée après qu'on lui
    /// a dit d'arrêter.
    private let awake = Awake()

    public init() {}

    public let id = "eveil"
    public let title = "Éveil"

    public var symbol: String {
        awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
    }

    /// Le temps restant, collé à l'icône de la barre : c'est la seule
    /// information qu'on veut lire sans rien ouvrir.
    public var badge: String? {
        guard let minutes = awake.minutesLeft, minutes > 0 else { return nil }
        return minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m"
    }

    public var summary: String {
        awake.isActive ? awake.summary : ""
    }

    public func makePanel() -> AnyView {
        AnyView(PanelView(awake: awake))
    }
}
