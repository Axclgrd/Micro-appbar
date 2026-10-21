import Foundation
import UserNotifications

/// Les notifications du système. Sans bundle (binaire lancé nu), le centre de
/// notifications plante : on ne s'en approche pas.
@MainActor
final class Notifications {
    private final class Delegue: NSObject, UNUserNotificationCenterDelegate, Sendable {
        // Trousse est un agent : sans ceci, une bannière arriverait muette
        // quand une de ses fenêtres est au premier plan.
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async
            -> UNNotificationPresentationOptions { [.banner, .list] }
    }

    private let delegue = Delegue()

    private var disponible: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private var centre: UNUserNotificationCenter? {
        guard disponible else { return nil }
        let c = UNUserNotificationCenter.current()
        c.delegate = delegue
        return c
    }

    @discardableResult
    func demander() async -> Bool {
        guard let centre else { return false }
        return (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// nil quand on ne peut pas le savoir.
    func refusees() async -> Bool? {
        guard let centre else { return nil }
        let reglages = await centre.notificationSettings()
        return reglages.authorizationStatus == .denied
    }

    func poster(_ titre: String, _ corps: String, id: String = UUID().uuidString) {
        guard let centre else { return }
        let contenu = UNMutableNotificationContent()
        contenu.title = titre
        contenu.body = corps
        centre.add(UNNotificationRequest(identifier: id, content: contenu, trigger: nil))
    }
}
