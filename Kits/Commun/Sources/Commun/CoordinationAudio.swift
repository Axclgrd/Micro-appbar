import Foundation

/// Ce que deux outils audio d'un même processus doivent savoir l'un de l'autre.
///
/// Nuit et Mélangeur posent tous deux des *taps* CoreAudio, et un tap reçoit
/// le son d'une app **avant** sa coupure. Si Mélangeur reprend Spotify à 40 %
/// pendant que la prise globale de Nuit tourne, Nuit reçoit lui aussi le
/// Spotify d'origine et le rejoue à pleine puissance : on entendrait les deux.
/// La prise globale doit donc exclure ce que Mélangeur rejoue lui-même.
///
/// Les deux vivent toujours dans le même processus : une app autonome cède sa
/// place à la trousse quand elle tourne, et Nuit n'existe que dans la trousse.
/// Une simple notification locale suffit, rien ne traverse les processus.
@MainActor
public enum CoordinationAudio {
    /// Posté quand l'ensemble des processus repris change.
    public static let changement = Notification.Name("local.microapp.audio.repris")

    /// Les objets-processus CoreAudio (`AudioObjectID`) que le mélangeur
    /// rejoue lui-même. Écrits en `UInt32` : `Commun` ne dépend pas de CoreAudio.
    public private(set) static var repris: Set<UInt32> = []

    /// Vrai tant que la prise globale de Nuit tourne. Le mélangeur s'en sert
    /// pour dire que les apps qu'il règle échappent au mode nuit.
    public static var nuitActive = false

    public static func declarer(_ processus: Set<UInt32>) {
        guard processus != repris else { return }
        repris = processus
        NotificationCenter.default.post(name: changement, object: nil)
    }
}
