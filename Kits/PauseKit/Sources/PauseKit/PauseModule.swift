import Commun
import SwiftUI

/// Met Apple Music en pause tant que le micro est utilisé.
///
/// Sur un Mac sans micro intégré, dicter avec des AirPods fait basculer le
/// casque en profil Bluetooth « appel » : son dégradé, volume qui s'envole.
/// Couper la musique avant que ça arrive évite les deux.
@MainActor
public final class PauseModule: Module {
    private let pause = Pause()

    public init() {}

    public let id = "pause"
    public let title = "Pause"

    public var symbol: String {
        switch pause.etat {
        case .musiqueEnPause: return "pause.circle.fill"
        case .microActif: return "mic.fill"
        default: return "pause.circle"
        }
    }

    public var summary: String { pause.resume }

    public func makePanel() -> AnyView {
        AnyView(PausePanel(pause: pause))
    }
}
