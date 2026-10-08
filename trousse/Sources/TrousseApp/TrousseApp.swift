import Commun
import SwiftUI

@main
struct TrousseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // L'app n'a pas de scène visible : ses fenêtres sont ouvertes à la
        // demande depuis la barre du haut. `Settings` sert de scène minimale
        // exigée par SwiftUI.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            BarController.shared.start()
            // On s'annonce : les apps autonomes déjà lancées s'effacent.
            Shared.broadcast("trousse.hello")
            // Chaque outil peut être appelé depuis son app autonome.
            for id in Registry.shared.ids {
                // On ne capture que l'identifiant : un module n'est pas
                // `Sendable`, une chaîne si.
                Shared.observe("reveal.\(id)") {
                    MainActor.assumeIsolated { BarController.shared.reveal(id) }
                }
            }
            // Ouvrir l'app, c'est demander à voir quelque chose. Une app agent
            // qui ne montre rien quand on la lance depuis le Dock ou Launchpad
            // paraît cassée — on double-clique, il ne se passe rien.
            Dashboard.shared.show()
        }
    }

    /// Relancer une app déjà lancée n'envoie pas de second démarrage, mais ce
    /// message-ci. Sans lui, ouvrir Trousse alors qu'elle tient déjà la barre
    /// du haut ne ferait rien du tout.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { Dashboard.shared.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
