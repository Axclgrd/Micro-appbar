import AppKit
import Commun
import SwiftUI

/// La fenêtre de composition.
///
/// Elle est tenue en AppKit plutôt qu'en scène SwiftUI : l'app n'a pas d'icône
/// dans le Dock ni de menu applicatif, et une scène `Window` ne s'ouvre alors
/// depuis nulle part. Ici, n'importe quel panneau peut l'appeler.
@MainActor
final class Dashboard: NSObject, NSWindowDelegate {
    static let shared = Dashboard()

    private var window: NSWindow?

    func show() {
        DockPresence.show()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Trousse"
        // Barre de titre effacée : le contenu porte le titre, et les pastilles
        // flottent au-dessus — c'est la disposition de la famille.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: DashboardView())
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.window = nil
            DockPresence.hideIfIdle()
        }
    }
}
