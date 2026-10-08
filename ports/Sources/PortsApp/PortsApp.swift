import Commun
import PortsKit
import SwiftUI

/// L'app autonome de Ports.
///
/// Elle n'a presque rien à faire : l'outil vit dans `PortsKit`, la coquille
/// dans `Commun`. Ce fichier n'apporte que l'icône et le fait d'exister — et
/// s'efface si Trousse est là.
@main
struct PortsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: MenuBarShell?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let shell = MenuBarShell(module: PortsModule())
            shell.start()
            self.shell = shell
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
