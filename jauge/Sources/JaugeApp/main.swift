import Commun
import Foundation
import JaugeKit
import SwiftUI

// Le même exécutable sert deux fois :
//
// - `Jauge --statusline`, appelé par Claude Code à chaque rafraîchissement de
//   sa ligne d'état : garde le relevé et rend la ligne, puis sort. Aucune
//   interface, pour rester instantané.
// - `Jauge --brancher` : ajoute la ligne d'état à ~/.claude/settings.json.
// - sans argument : l'app de la barre des menus.
let arguments = CommandLine.arguments
if arguments.contains("--statusline") {
    StatusLine.run()
    exit(0)
}
if arguments.contains("--brancher") {
    let state = Hookup.install(executable: Bundle.main.executablePath ?? arguments[0])
    switch state {
    case .connected: print("Claude Code est branché sur Jauge.")
    case .absent: print("Le branchement a échoué : ~/.claude/settings.json est illisible ou protégé.")
    case .occupied(let command): print("Une autre ligne d'état est déjà réglée, Jauge n'y touche pas : \(command)")
    }
    exit(state == .connected ? 0 : 1)
}

JaugeApp.main()

/// L'app autonome de Jauge. L'outil vit dans `JaugeKit`, la coquille dans
/// `Commun` : ce fichier n'apporte que l'icône, et le fait de s'effacer si
/// Trousse est là.
struct JaugeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shell: MenuBarShell?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let shell = MenuBarShell(module: JaugeModule())
            shell.start()
            self.shell = shell
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
