import Commun
import SwiftUI

/// Le mélangeur : chaque application à son volume, chaque son à sa sortie.
///
/// Réglages Système sait choisir *une* sortie et *un* volume pour tout le Mac.
/// Il ne sait pas baisser Slack sans baisser Spotify, ni envoyer un appel dans
/// le casque pendant que la musique reste sur les enceintes. C'est ce qui
/// manque, et c'est tout ce que fait cet outil — en plus de rassembler sur un
/// seul panneau les sorties, les entrées et les alertes.
@MainActor
public final class MelangeurModule: Module {
    private let melangeur = Melangeur()

    public init() {}

    public let id = "melangeur"
    public let title = "Mélangeur"
    public let symbol = "slider.vertical.3"

    public var summary: String { melangeur.resume }

    public func activate() { melangeur.panelVisible = true }
    public func idle() { melangeur.panelVisible = false }

    public func makePanel() -> AnyView {
        AnyView(MelangeurPanel(melangeur: melangeur))
    }
}
