import AppKit
import Observation

/// Le terrain commun aux six apps et à la trousse.
///
/// Deux besoins seulement : ranger les réglages au même endroit, et se prévenir
/// entre processus quand quelque chose change. Pas de base, pas de serveur —
/// un domaine de préférences partagé et une notification distribuée suffisent,
/// et survivent à l'absence de l'un ou l'autre.
public enum Shared {
    /// L'identifiant de la trousse. Il vit ici, hors de `Presence`, pour être
    /// lisible depuis un contexte non isolé — une notification de `NSWorkspace`
    /// arrive avant qu'on ait rejoint le fil principal.
    public static let trousseIdentifier = "local.trousse"

    /// Un domaine à part, hors du `local.eveil` ou `local.trousse` de chacun :
    /// c'est ce qui permet à l'app autonome et à la trousse de lire le même
    /// réglage sans se marcher dessus.
    public static let suite = "local.microapp"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: suite) ?? .standard
    }

    /// Prévient les autres processus. Le nom est libre, par convention celui de
    /// l'outil concerné.
    public static func broadcast(_ topic: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("local.microapp.\(topic)"),
            object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Écoute les changements venus d'ailleurs. `handler` est appelé sur le
    /// fil principal.
    @discardableResult
    public static func observe(_ topic: String, _ handler: @escaping @Sendable () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.microapp.\(topic)"),
            object: nil, queue: .main) { _ in handler() }
    }
}

/// Qui est là.
///
/// Une app autonome doit savoir si la trousse tourne : sans ça, l'utilisateur
/// aurait deux icônes pour le même outil, et deux panneaux qui se contredisent.
@MainActor
@Observable
public final class Presence {
    public static let shared = Presence()

    public private(set) var trousseIsRunning: Bool

    private init() {
        trousseIsRunning = Self.look()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    Presence.shared.trousseIsRunning = Presence.look()
                }
            }
        }
    }

    private static func look() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: Shared.trousseIdentifier).contains {
            !$0.isTerminated
        }
    }
}
