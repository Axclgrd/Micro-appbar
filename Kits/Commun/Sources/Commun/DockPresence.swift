import AppKit

/// L'icône dans le Dock, le temps qu'on s'en serve.
///
/// Les outils de la barre des menus sont des agents : pas d'icône dans le Dock,
/// pas de menu applicatif. C'est ce qu'on veut quand ils dorment — une icône
/// permanente pour un outil qu'on ouvre trois fois par jour encombre pour rien.
///
/// Mais dès qu'une vraie fenêtre s'ouvre, l'inverse devient vrai : on veut
/// pouvoir revenir dessus d'un clic, la retrouver par ⌘⇥, la fermer par ⌘W —
/// et voir son icône, qui n'est pas là par hasard. La politique d'activation
/// bascule donc à l'ouverture et revient à la fermeture de la dernière fenêtre.
@MainActor
public enum DockPresence {

    /// Une fenêtre s'ouvre : l'app entre dans le Dock.
    public static func show() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        // Sans cette réactivation, la fenêtre s'ouvre derrière celle d'à côté :
        // changer de politique fait perdre le premier plan à l'app.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Une fenêtre se ferme : on ne quitte le Dock que s'il n'en reste aucune.
    ///
    /// L'appel est différé d'un tour de boucle parce qu'au moment où le système
    /// prévient de la fermeture, la fenêtre est encore comptée parmi les
    /// visibles — on conclurait qu'il en reste une.
    public static func hideIfIdle() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let visible = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
                guard !visible, NSApp.activationPolicy() != .accessory else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
