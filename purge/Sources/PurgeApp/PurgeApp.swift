import Commun
import PurgeKit
import SwiftUI

/// L'app autonome de Purge. L'analyse et la fenêtre vivent dans `PurgeKit` —
/// ce sont les mêmes que celles ouvertes depuis Trousse.
@main
struct PurgeApp: App {
    @State private var store = PurgeStore()

    var body: some Scene {
        Window("Purge", id: "purge") {
            ContentView(store: store)
        }
        // Une seule fenêtre : deux analyses en parallèle ne veulent rien dire,
        // et la barre de titre masquée laisse le contenu porter l'identité.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}


