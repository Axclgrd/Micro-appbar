import Commun
import GrabKit
import SwiftUI

/// L'app autonome de Grab. Le raccourci global et l'OCR vivent dans `GrabKit`.
@main
struct GrabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: MenuBarShell?
    private var module: GrabModule?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let module = GrabModule()
            let shell = MenuBarShell(module: module)
            shell.start()
            self.module = module
            self.shell = shell
        }
    }

    /// Relancer une app déjà lancée ne fait rien de visible quand elle n'a ni
    /// fenêtre ni icône. On s'en sert donc comme d'un interrupteur : c'est le
    /// seul geste évident pour retrouver une icône qu'on a masquée.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { module?.revealIcon() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
