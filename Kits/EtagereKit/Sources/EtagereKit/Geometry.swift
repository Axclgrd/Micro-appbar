import AppKit

/// Les mesures de la tablette.
///
/// Elles sont fixes plutôt que proportionnelles à l'écran : l'étagère doit
/// avoir la même taille sur le portable et sur le moniteur branché à côté,
/// sinon le geste appris sur l'un est faux sur l'autre.
enum Metric {
    static let tile: CGFloat = 72
    static let gap: CGFloat = 9
    static let pad: CGFloat = 12
    static var shelfHeight: CGFloat { tile + pad * 2 }

    /// Marge sous la tablette, réservée à son ombre. La fenêtre est transparente :
    /// sans cette réserve l'ombre serait coupée net au bord.
    static let shadow: CGFloat = 20

    static let minWidth: CGFloat = 250

    /// Douze objets, pas plus. Au treizième le plus ancien s'en va : une étagère
    /// où l'on empile sans jamais retirer redevient le bureau qu'on fuyait.
    static let capacity = 12

    /// La profondeur de la zone sensible quand la tablette dort.
    ///
    /// Sur un écran à encoche elle vaut presque rien, parce que l'encoche
    /// elle-même — trente-huit points sans un pixel derrière, où aucun clic ne
    /// sert à rien — fait déjà l'essentiel de la cible. Sur un écran sans
    /// encoche il n'y a rien de tel : la bande doit être assez épaisse pour
    /// qu'un glisser qui monte jusqu'en butée la touche, et elle mord alors sur
    /// le haut du contenu.
    static let idleDepthNotched: CGFloat = 5
    static let idleDepthPlain: CGFloat = 14

    /// Quand on sait qu'un glisser est en cours, la cible s'élargit : viser
    /// devient inutile. En dehors de ce moment la fenêtre reste minuscule,
    /// parce qu'une fenêtre invisible qui traîne en haut de l'écran avale les
    /// clics de celle du dessous.
    static let catchWings: CGFloat = 130
    static let catchDepth: CGFloat = 26

    /// L'éveil : deux ou trois points d'épaisseur en plus sous l'encoche.
    static let awakeThickness: CGFloat = 3
    /// Le souvenir : plus étroit que l'encoche, et à peine plus épais que rien.
    /// Large et très peu profond, parce qu'un renflement doux se lit comme une
    /// déformation de l'encoche, là où un trait court et net se lit comme un
    /// objet posé dessous.
    static let bulgeWidth: CGFloat = 64
    static let bulgeThickness: CGFloat = 4

    /// La largeur de la tablette pour un nombre d'objets donné.
    static func width(for count: Int) -> CGFloat {
        guard count > 0 else { return minWidth }
        let content = CGFloat(count) * tile + CGFloat(count - 1) * gap + pad * 2
        return max(minWidth, content)
    }
}

/// Où la tablette se pose, et d'où elle sort.
///
/// Tout est déduit de `NSScreen` : l'encoche n'est pas devinée, elle est
/// exactement l'espace laissé entre les deux zones que macOS déclare
/// utilisables de part et d'autre — 220 points sur ce MacBook Pro, avec 790
/// points libres à gauche et autant à droite.
struct ShelfGeometry: Equatable {
    let screen: CGRect
    let hasNotch: Bool
    /// La largeur du volet noir : l'encoche réelle, ou une largeur de
    /// convention sur un écran qui n'en a pas.
    let lipWidth: CGFloat
    let centerX: CGFloat
    /// Le haut de la fenêtre. Sur un écran à encoche c'est le bord de l'écran :
    /// la fenêtre couvre l'encoche, qui devient ainsi une cible de glisser
    /// gratuite. Ailleurs c'est le bas de la barre des menus, qu'il ne faut
    /// surtout pas recouvrir.
    let windowTop: CGFloat
    /// L'ordonnée d'où la tablette se déplie — le bas de l'encoche.
    let emergeY: CGFloat

    var notchHeight: CGFloat { windowTop - emergeY }
    var idleDepth: CGFloat { hasNotch ? Metric.idleDepthNotched : Metric.idleDepthPlain }

    /// L'écran qui porte l'étagère : celui qui a une encoche, sinon le
    /// principal. Choisir « l'écran où est la souris » ferait sauter la tablette
    /// d'un écran à l'autre en cours de geste.
    static func current() -> ShelfGeometry {
        let screens = NSScreen.screens
        let host = screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? screens.first
        guard let host else {
            return ShelfGeometry(screen: .zero, hasNotch: false, lipWidth: 220,
                                 centerX: 0, windowTop: 0, emergeY: 0)
        }
        let frame = host.frame

        if let left = host.auxiliaryTopLeftArea, let right = host.auxiliaryTopRightArea,
           right.minX > left.maxX {
            return ShelfGeometry(
                screen: frame,
                hasNotch: true,
                lipWidth: right.minX - left.maxX,
                centerX: (left.maxX + right.minX) / 2,
                windowTop: frame.maxY,
                emergeY: frame.maxY - host.safeAreaInsets.top)
        }

        // Sans encoche, la tablette se pose au centre du bord haut, juste sous
        // la barre des menus. `visibleFrame` la retire déjà — et retire aussi
        // le Dock, d'où le calcul par le haut seulement.
        return ShelfGeometry(
            screen: frame,
            hasNotch: false,
            lipWidth: 220,
            centerX: frame.midX,
            windowTop: host.visibleFrame.maxY,
            emergeY: host.visibleFrame.maxY)
    }

    /// Le cadre de la fenêtre pour une profondeur et une largeur données,
    /// recentré sur l'encoche et maintenu dans l'écran.
    func frame(width: CGFloat, depth: CGFloat) -> NSRect {
        let clamped = min(width, screen.width - 40)
        var x = centerX - clamped / 2
        x = min(max(x, screen.minX + 20), screen.maxX - 20 - clamped)
        return NSRect(x: x, y: emergeY - depth, width: clamped, height: depth + notchHeight)
    }
}
