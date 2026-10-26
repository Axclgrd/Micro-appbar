import Commun
import SwiftUI

/// Le pouls de la machine : ce qui consomme, et ce qu'on peut y faire.
///
/// Le Moniteur d'activité d'Apple répond déjà à « combien » ; il ne répond pas
/// à « est-ce normal » ni à « que faire ». Cet outil s'arrête là où commence
/// le Moniteur d'activité : cinq ressources, les applications regroupées,
/// trois conseils au plus, et rien à configurer.
@MainActor
public final class PoulsModule: Module {
    private let pouls = Pouls()

    public init() {
        // Cadence lente d'emblée : c'est ce qui alimente l'icône et la ligne
        // d'état. Le détail par application attend l'ouverture du panneau.
        pouls.start()
    }

    public let id = "pouls"
    public let title = "Pouls"

    public var symbol: String { pouls.etat.symbol }

    public var badge: String? {
        pouls.badgeEnabled ? Chiffre.part(pouls.cpu.total) : nil
    }

    public var summary: String {
        guard let memory = pouls.memory else { return "" }
        return "\(Chiffre.part(pouls.cpu.total)) · \(Chiffre.octets(memory.used))"
    }

    public func activate() { pouls.panelVisible = true }
    public func idle() { pouls.panelVisible = false }

    public func makePanel() -> AnyView {
        AnyView(PoulsPanel(pouls: pouls))
    }
}
