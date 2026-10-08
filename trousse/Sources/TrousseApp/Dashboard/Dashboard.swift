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

        // Une fenêtre standard : barre de titre et barre d'outils du système
        // (en verre sur macOS 26), barre latérale qui passe sous elles.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Trousse"
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 640, height: 440)
        window.contentViewController = NSHostingController(rootView: DashboardView())
        window.setContentSize(NSSize(width: 760, height: 520))
        window.setFrameAutosaveName("TrousseDashboard")
        if !window.setFrameUsingName("TrousseDashboard") { window.center() }
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
