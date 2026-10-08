import Commun
import SwiftUI

@MainActor
public final class FanModule: Module {
    private let monitor = Monitor()
    private let commander = FanCommander()

    public init() {
        // Le moniteur démarre tout de suite, en cadence lente : c'est ce qui
        // alimente la température collée à l'icône. C'était déjà le
        // comportement de l'app autonome.
        monitor.start()
        Task { await commander.probe() }
    }

    public let id = "fancontrole"
    public let title = "Ventilateurs"

    public var symbol: String {
        commander.isManual ? "fanblades.fill" : "fanblades"
    }

    /// La température du point chaud, en degrés entiers. Volontairement
    /// grossière : c'est ce qui rend l'icône insensible aux dixièmes de degré,
    /// et donc silencieuse côté redessin.
    public var badge: String? {
        monitor.hotspotDisplay.map { "\($0)°" }
    }

    public var summary: String {
        guard let hotspot = monitor.hotspotDisplay else { return "" }
        return commander.isManual ? "\(hotspot)° · manuel" : "\(hotspot)°"
    }

    public func activate() {
        monitor.panelVisible = true
        // Le démon peut être installé après le lancement : on retente la
        // connexion à chaque ouverture.
        Task { await commander.probe() }
    }

    public func idle() {
        monitor.panelVisible = false
    }

    public func makePanel() -> AnyView {
        AnyView(PanelView(monitor: monitor, commander: commander))
    }
}
