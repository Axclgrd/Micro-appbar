import BandeKit
import Commun
import EjecterKit
import EtagereKit
import EveilKit
import FanKit
import FonteKit
import GrabKit
import JaugeKit
import MajKit
import MelangeurKit
import NuitKit
import PauseKit
import PortsKit
import PoulsKit
import PurgeKit
import SwiftUI

/// Le catalogue des outils compilés dans la trousse.
///
/// Volontairement statique : la trousse n'a pas de greffons, elle a des
/// bibliothèques qu'on ajoute en recompilant. C'est ce qui lui garde une seule
/// identité, une seule signature, une seule autorisation — et c'est aussi ce
/// qui fait que chaque outil n'existe qu'en un seul exemplaire, partagé avec
/// son app autonome.
@MainActor
final class Registry {
    static let shared = Registry()

    private(set) var modules: [Module] = []

    private init() {
        modules = [
            FanModule(),
            PoulsModule(),
            MelangeurModule(),
            EjecterModule(),
            EveilModule(),
            PortsModule(),
            PurgeModule(),
            BandeModule(),
            EtagereModule(),
            GrabModule(),
            FonteModule(),
            JaugeModule(),
            PauseModule(),
            MajModule(),
            NuitModule(),
        ]
    }

    func module(_ id: String) -> Module? {
        modules.first { $0.id == id }
    }

    var ids: [String] { modules.map(\.id) }
}
