import Commun
import SwiftUI

@MainActor
public final class GrabModule: Module {
    private let grabber = Grabber.shared

    public init() {}

    public let id = "grab"
    public let title = "Grab"

    public var symbol: String {
        grabber.working ? "viewfinder" : "text.viewfinder"
    }

    /// Grab n'a pas besoin d'icône : son raccourci suffit. C'est l'outil qui
    /// justifie le mieux la notion de « masqué » — dans Trousse, il se range
    /// simplement là.
    public var isRelevant: Bool { grabber.showIcon }

    public var summary: String {
        if grabber.working { return "capture…" }
        return grabber.captures > 0 ? "\(grabber.captures) capture\(grabber.captures > 1 ? "s" : "")" : ""
    }

    /// Rend l'icône après qu'on l'a masquée. C'est le geste « relancer l'app »
    /// de la coquille autonome ; la trousse, elle, range Grab dans un groupe ou
    /// dans les masqués.
    public func revealIcon() {
        grabber.showIcon = true
    }

    public func activate() {
        grabber.refreshPermission()
        // Ouvrir le panneau, c'est vouloir s'en servir : c'est le bon moment
        // pour que macOS pose sa question, et pour que l'app existe dans la
        // liste des Réglages.
        grabber.askQuietly()
    }

    public func makePanel() -> AnyView {
        AnyView(PanelView(grabber: grabber))
    }
}
