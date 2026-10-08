import Commun
import EveilKit
import SwiftUI

/// L'app autonome d'Éveil.
///
/// L'outil vit dans `EveilKit`, la coquille dans `Commun` : ce fichier n'apporte
/// que l'icône, et le fait de s'effacer si Trousse est là.
@main
struct EveilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: MenuBarShell?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let shell = MenuBarShell(module: EveilModule())
            shell.start()
            self.shell = shell
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
