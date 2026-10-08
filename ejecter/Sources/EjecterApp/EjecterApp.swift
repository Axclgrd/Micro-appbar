import Commun
import EjecterKit
import SwiftUI

/// L'app autonome d'Éjecter. L'outil vit dans `EjecterKit`, la coquille dans
/// `Commun` — y compris la règle qui fait disparaître l'icône quand aucun
/// disque externe n'est branché.
@main
struct EjecterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: MenuBarShell?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let shell = MenuBarShell(module: EjecterModule())
            shell.start()
            self.shell = shell
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
