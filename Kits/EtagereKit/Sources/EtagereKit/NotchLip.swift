import SwiftUI

/// Le bourrelet sous l'encoche : l'éveil quand un glisser est en cours, le
/// souvenir quand des objets attendent.
///
/// Trois décisions tiennent tout le dessin, et elles viennent d'une capture
/// d'écran ratée : un simple rectangle noir posé sous l'encoche ne se lit pas
/// comme une encoche épaissie, mais comme un trait collé par-dessus le fond
/// d'écran.
///
/// 1. **La forme remonte derrière l'encoche** (`rise`). Il n'y a pas un pixel
///    d'écran là — le boîtier de la caméra les cache — donc c'est gratuit, et
///    ça garantit qu'aucune couture d'un demi-point ne peut apparaître au
///    raccord, quelle que soit l'arrondi du calcul de mise en page.
/// 2. **Les extrémités s'évasent** (`flare`). Une goutte qui pend d'une barre
///    ne la rejoint pas à angle droit : le raccord est un congé concave. C'est
///    ce congé, et lui seul, qui fait croire à une continuité de matière.
/// 3. **Le raccord est tangent, pas seulement arrondi.** Les congés partent et
///    arrivent à l'horizontale. Une courbe quadratique laisse un angle résiduel
///    à chaque bout — invisible sur un dessin de vingt points, criant sur un
///    bourrelet de trois.
struct NotchLip: Shape {
    /// La largeur au niveau du bord de l'encoche, congés compris.
    var span: CGFloat
    /// Ce qui dépasse sous l'encoche. C'est la seule part visible.
    var depth: CGFloat
    /// Ce qui remonte derrière l'encoche, invisible.
    var rise: CGFloat
    /// La largeur du congé de raccord, de chaque côté.
    var flare: CGFloat

    /// Seule la profondeur s'anime : c'est elle qui dit « quelque chose arrive »
    /// et « quelque chose attend ».
    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard depth > 0.05, span > 0 else { return path }

        let cx = rect.midX
        let line = rect.minY + rise
        let bottom = line + depth
        let half = span / 2
        let inner = max(half - flare, 0)
        let reach = max(half - inner, 0.001)

        // Tangente horizontale aux deux bouts de chaque congé : au raccord avec
        // le bord droit de l'encoche comme au raccord avec le fond plat. C'est
        // la condition pour qu'aucune cassure ne se voie — une simple courbe
        // quadratique laisse un petit angle à chaque extrémité, parfaitement
        // visible à trois points de profondeur.
        path.move(to: CGPoint(x: cx - half, y: line))
        path.addCurve(to: CGPoint(x: cx - inner, y: bottom),
                      control1: CGPoint(x: cx - half + reach * 0.55, y: line),
                      control2: CGPoint(x: cx - inner - reach * 0.55, y: bottom))
        path.addLine(to: CGPoint(x: cx + inner, y: bottom))
        path.addCurve(to: CGPoint(x: cx + half, y: line),
                      control1: CGPoint(x: cx + inner + reach * 0.55, y: bottom),
                      control2: CGPoint(x: cx + half - reach * 0.55, y: line))
        path.addLine(to: CGPoint(x: cx + half, y: rect.minY))
        path.addLine(to: CGPoint(x: cx - half, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
