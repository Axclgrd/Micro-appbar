import AppKit
import SwiftUI

/// Le vocabulaire des mouvements.
///
/// Trois règles, et elles suffisent à tenir l'ensemble : tout part de l'encoche
/// et y retourne, rien ne dépasse le quart de seconde, et il n'y a qu'un seul
/// rebond dans tout l'outil — celui de la pose, qui dit « c'est fait ».
///
/// L'ouverture est plus lente que le repli. Ouvrir invite : on a le temps de
/// voir d'où ça sort. Fermer est un renoncement — le faire attendre serait le
/// punir.
enum Motion {
    /// Quand « Réduire les animations » est actif, tout devient instantané.
    /// Aucune fonction ne disparaît : l'étagère se comporte exactement pareil,
    /// elle ne raconte simplement plus le trajet.
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Le tiroir qui sort. Sans rebond : le seul est réservé à la pose.
    static var unfold: Animation? { reduced ? nil : .spring(duration: 0.24, bounce: 0) }
    /// Le repli, nettement plus court que l'ouverture.
    static var fold: Animation? { reduced ? nil : .easeIn(duration: 0.14) }
    /// L'écartement des objets, et la place qui se creuse.
    static var shift: Animation? { reduced ? nil : .spring(duration: 0.18, bounce: 0) }
    /// L'éveil : lent à venir, discret. Une main qui se lève au fond de la
    /// classe, pas une alarme — d'où le retard à l'allumage.
    static var wake: Animation? { reduced ? nil : .easeOut(duration: 0.22).delay(0.08) }
    /// La reprise : l'objet se soulève.
    static var lift: Animation? { reduced ? nil : .spring(duration: 0.16, bounce: 0) }
}

/// Le lien de la vue vers le contrôleur, sans cycle de rétention.
///
/// La fenêtre tient la vue, qui tiendrait le contrôleur, qui tient la fenêtre :
/// une référence faible cassée en un seul endroit vaut mieux que trois `weak`
/// disséminés dans des structures de vue.
@MainActor
final class ShelfLink {
    weak var controller: ShelfController?
}
