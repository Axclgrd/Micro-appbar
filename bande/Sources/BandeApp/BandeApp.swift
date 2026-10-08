import BandeKit
import Commun
import SwiftUI

/// L'app autonome de Bande. L'extraction et la fenêtre vivent dans `BandeKit` —
/// ce sont les mêmes que celles ouvertes depuis Trousse.
@main
struct BandeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Bande", id: "bande") {
            ContentView(store: .shared)
        }
        // Une seule fenêtre : la file d'attente est unique, deux fenêtres
        // feraient croire à deux files.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 560, height: 470)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Ouvrir une vidéo…") { BandeStore.shared.choose() }
                    .keyboardShortcut("o")
            }
        }
    }
}

/// Le délégué n'existe que pour une chose : recevoir les vidéos lâchées sur
/// l'icône du Dock. SwiftUI ne l'expose pas, et c'est le geste le plus naturel
/// quand la fenêtre est fermée.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            BandeStore.shared.add(urls)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
