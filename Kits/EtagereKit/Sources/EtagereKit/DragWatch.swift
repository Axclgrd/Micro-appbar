import AppKit
import Observation

/// Savoir qu'un glisser est en cours, n'importe où dans le système, sans rien
/// demander à l'utilisateur.
///
/// La question a été tranchée à la mesure, pas au raisonnement :
///
/// - Un moniteur global `NSEvent` sur les évènements **souris** fonctionne sans
///   l'autorisation d'accessibilité — vérifié avec `AXIsProcessTrusted()` à
///   `false`. C'est le clavier qui est protégé, pas la souris ; d'où la
///   différence avec Grab, qui passe par Carbon pour son raccourci.
/// - Le presse-papier de glisser (`NSPasteboard(name: .drag)`) voit son
///   compteur de modifications avancer dès qu'une app — n'importe laquelle —
///   ouvre une session de glisser. Mesuré : compteur 8 → 9 au démarrage d'une
///   session dans un autre processus.
///
/// D'où la règle : au clic, on retient le compteur ; tant que le bouton est
/// tenu, s'il a bougé, c'est qu'un glisser est né de ce clic-là. Le contenu du
/// presse-papier n'est **jamais** lu — seulement son compteur, qui n'est qu'un
/// entier et ne déclenche aucune demande de confidentialité.
///
/// Le sondage ne tourne que pendant qu'un bouton est enfoncé. Souris au repos,
/// l'outil ne coûte rien.
@MainActor
@Observable
final class DragWatch {
    static let shared = DragWatch()

    /// Vrai quand quelque chose est soulevé quelque part.
    private(set) var lifted = false

    private var monitors: [Any] = []
    private var mark = 0
    private var poll: Timer?

    private init() {}

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { DragWatch.shared.handle(event.type) }
        }) {
            monitors.append(global)
        }
        // Le moniteur global ignore les évènements de notre propre app : sans
        // celui-ci, reprendre un objet sur la tablette ne serait pas vu.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { DragWatch.shared.handle(event.type) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        release()
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown: press()
        case .leftMouseUp: release()
        default: break
        }
    }

    private func press() {
        mark = NSPasteboard(name: .drag).changeCount
        lifted = false
        poll?.invalidate()
        // Soixante millisecondes : assez fin pour que l'encoche se lève pendant
        // que la main monte encore, assez lâche pour ne rien peser.
        poll = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
            MainActor.assumeIsolated { DragWatch.shared.look() }
        }
    }

    private func look() {
        // Pendant une session de glisser, le lâcher du bouton est consommé par
        // le gestionnaire de glisser et n'arrive jamais au moniteur. L'état réel
        // des boutons est donc la seule fin de course fiable.
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            release()
            return
        }
        if !lifted, NSPasteboard(name: .drag).changeCount != mark {
            lifted = true
        }
    }

    private func release() {
        poll?.invalidate()
        poll = nil
        lifted = false
    }
}
