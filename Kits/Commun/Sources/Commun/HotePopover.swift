import AppKit
import SwiftUI

/// Le contenu SwiftUI d'un popover de la barre des menus, et sa taille.
///
/// Laissé à lui-même, un `NSPopover` s'ouvre à sa taille par défaut, 320 × 320,
/// et ne prend celle de son contenu qu'au tour de boucle suivant. Mesuré : à
/// l'ouverture, la liste de Trousse (192 pt) flottait 77 pt trop bas, et un
/// panneau de 557 pt comme Pouls voyait sa première image rognée en haut et en
/// bas — d'où l'effet « écrasé » au premier clic.
///
/// Trois réglages, tous nécessaires :
/// 1. la taille est calculée *avant* l'affichage (`ouvrir`) ;
/// 2. SwiftUI tient ensuite la taille du popover à jour quand le contenu
///    change, par exemple en passant de la liste d'un groupe à un outil ;
/// 3. le contenu reste ancré en haut, à sa hauteur idéale : si la fenêtre
///    tarde d'une image, le bas attend au lieu que tout se décale.
@MainActor
public enum HotePopover {
    public static func controleur<V: View>(_ vue: V, largeur: CGFloat) -> NSHostingController<AnyView> {
        let racine = vue
            .frame(width: largeur)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .top)
        let controleur = NSHostingController(rootView: AnyView(racine))
        controleur.sizingOptions = [.preferredContentSize]
        return controleur
    }

    /// Affiche le popover à la bonne taille dès la première image.
    public static func ouvrir(_ popover: NSPopover, sur vue: NSView) {
        if let contenu = popover.contentViewController?.view {
            popover.contentSize = contenu.fittingSize
        }
        popover.show(relativeTo: vue.bounds, of: vue, preferredEdge: .minY)
    }
}
