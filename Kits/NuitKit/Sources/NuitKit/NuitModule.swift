import Commun
import SwiftUI

/// Stabilisateur audio : lisse le volume de tout le son du Mac (mode nuit).
///
/// Clé à ajouter à l'Info.plist de l'app hôte : `NSAudioCaptureUsageDescription`.
@MainActor
public final class NuitModule: Module {
    private let nuit = Nuit()

    public init() {}

    public let id = "nuit"
    public let title = "Nuit"

    public var symbol: String {
        switch nuit.etat {
        case .actif, .enAttente, .demarrage: return "moon.stars.fill"
        default: return "moon.stars"
        }
    }

    public var summary: String { nuit.resume }

    public func activate() { nuit.activate() }
    public func idle() { nuit.idle() }

    public func makePanel() -> AnyView {
        AnyView(NuitPanel(nuit: nuit))
    }
}
