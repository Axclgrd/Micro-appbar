import Commun
import FanKit
import SwiftUI

/// L'app autonome de fancontrole. La lecture du SMC, le dialogue avec le démon
/// et le panneau vivent dans `FanKit` — Trousse affiche exactement le même.
///
/// Le démon root, lui, ne change pas : il est installé par `install.sh` et
/// n'a rien à voir avec l'interface qui le pilote.
@main
struct FanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: MenuBarShell?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let shell = MenuBarShell(module: FanModule())
            shell.start()
            self.shell = shell
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
