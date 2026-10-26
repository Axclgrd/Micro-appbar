import Foundation

/// Le volume des alertes : le bip, les sons de notification.
///
/// CoreAudio ne l'expose pas — c'est un réglage du serveur de sons système,
/// pas d'un périphérique. La seule voie publique est la commande AppleScript
/// `volume settings`, celle de Réglages Système eux-mêmes. Elle s'exécute dans
/// notre processus, sans envoyer d'événement à une autre app : aucune
/// autorisation d'automatisation n'est demandée.
@MainActor
enum Alertes {
    /// 0 à 1, ou `nil` si la lecture échoue.
    static func volume() -> Double? {
        var erreur: NSDictionary?
        guard let resultat = NSAppleScript(source: "alert volume of (get volume settings)")?
            .executeAndReturnError(&erreur),
              erreur == nil
        else { return nil }
        let v = Double(resultat.int32Value)
        return min(1, max(0, v / 100))
    }

    static func regler(_ valeur: Double) {
        let pourcent = Int((min(1, max(0, valeur)) * 100).rounded())
        var erreur: NSDictionary?
        NSAppleScript(source: "set volume alert volume \(pourcent)")?.executeAndReturnError(&erreur)
    }
}
