import Commun
import FonteKit
import SwiftUI

/// L'app autonome de Fonte. Le raccourci, la capture, l'analyse et la fenêtre
/// vivent dans `FonteKit` — ce sont les mêmes que ceux de Trousse.
@main
struct FonteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: MenuBarShell?
    private var module: FonteModule?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let module = FonteModule()
            let shell = MenuBarShell(module: module)
            shell.start()
            self.module = module
            self.shell = shell
        }
    }

    /// Relancer l'app, c'est demander à la voir : l'icône revient si on
    /// l'avait masquée, et l'historique s'ouvre.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            module?.revealIcon()
            module?.open()
        }
        return true
    }

    /// Une image lâchée sur l'app, ou ouverte avec elle.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { FonteStore.shared.receive(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
