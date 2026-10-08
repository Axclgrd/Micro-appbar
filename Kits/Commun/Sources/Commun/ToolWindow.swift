import AppKit
import SwiftUI

/// Une fenêtre d'outil, ouverte à la demande.
///
/// Purge et Bande ne sont pas des panneaux : ils demandent à lire avant d'agir,
/// donc une vraie fenêtre. Depuis la trousse, leur module n'affiche qu'un
/// résumé et le bouton qui ouvre celle-ci — c'est la même fenêtre que celle de
/// leur app autonome, au même endroit dans le code.
@MainActor
public final class ToolWindow: NSObject, NSWindowDelegate {
    private let title: String
    private let size: NSSize
    private let content: () -> AnyView
    private var window: NSWindow?

    public init(title: String, size: NSSize, content: @escaping () -> AnyView) {
        self.title = title
        self.size = size
        self.content = content
    }

    public func show() {
        DockPresence.show()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = title
        // Barre de titre effacée : le contenu porte le titre, comme dans les
        // apps autonomes de la famille.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: content())
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    public nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.window = nil
            DockPresence.hideIfIdle()
        }
    }
}


/// Ouvrir l'app d'un outil, quand elle est installée.
///
/// Purge et Bande ne sont pas des panneaux : ce sont des apps, avec leur
/// fenêtre, leur icône dans le Dock et leur propre cycle de mise à jour. La
/// trousse a d'abord recopié leur fenêtre chez elle — et le résultat était
/// déroutant : ouvrir Bande depuis le Dock donnait une fenêtre appartenant à
/// Trousse, sans l'icône de Bande, et figée à la version de Trousse.
///
/// Elle les lance donc, au lieu de les imiter. Il n'y a qu'une seule Bande.
@MainActor
public enum ExternalApp {
    /// Rend `false` si l'app n'est pas installée — l'appelant se rabat alors
    /// sur sa propre fenêtre, pour que l'outil marche quand même.
    @discardableResult
    public static func open(_ bundleIdentifier: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }
}
