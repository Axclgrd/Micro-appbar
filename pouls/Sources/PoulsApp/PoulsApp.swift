import Commun
import PoulsKit
import SwiftUI

/// L'app autonome de Pouls.
///
/// Comme ses sœurs, elle n'apporte que l'icône et le fait d'exister : l'outil
/// vit dans `PoulsKit`, la coquille dans `Commun`. Si Trousse tourne, elle lui
/// passe la main et s'efface.
@main
struct PoulsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: MenuBarShell?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let shell = MenuBarShell(module: PoulsModule())
            shell.start()
            self.shell = shell
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
