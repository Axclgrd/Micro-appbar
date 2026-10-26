import AppKit

/// Referme un panneau quand on clique ailleurs.
///
/// Un `NSPopover` en `.transient` est censé le faire seul, mais seulement si
/// son app est active. Une app de la barre des menus ne l'est jamais : ouvrir
/// son panneau ne doit pas voler le focus à l'app où l'on travaille. Le clic
/// suivant, dans une autre fenêtre, part donc vers une autre app sans que la
/// nôtre en sache rien — et le panneau reste ouvert jusqu'à ce qu'on reclique
/// sur l'icône.
///
/// Un moniteur *global* reçoit précisément ces clics-là : ceux destinés aux
/// autres apps, y compris aux autres icônes de la barre. Les clics dans notre
/// propre panneau, ses menus ou sur notre icône restent locaux et ne le
/// déclenchent pas. Les événements souris ne demandent aucune autorisation,
/// contrairement aux touches du clavier.
@MainActor
public final class ClicAilleurs {
    private var moniteur: Any?

    public init() {}

    public func surveiller(_ action: @escaping @MainActor () -> Void) {
        arreter()
        moniteur = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            // Les moniteurs globaux sont appelés sur le fil principal.
            MainActor.assumeIsolated { action() }
        }
    }

    public func arreter() {
        guard let moniteur else { return }
        NSEvent.removeMonitor(moniteur)
        self.moniteur = nil
    }
}
