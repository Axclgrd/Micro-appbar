import AppKit
import Commun
import Observation
import UserNotifications

/// La consommation de l'abonnement Claude, et les alertes qui vont avec.
///
/// Rien ne sonde : le dossier des relevés est surveillé par le système, et
/// Jauge ne se réveille que quand Claude Code y écrit — c'est-à-dire quand
/// on s'en sert, le seul moment où la jauge peut bouger.
@MainActor
@Observable
public final class Jauge {

    public static let shared = Jauge()

    public private(set) var usage: Usage?
    public private(set) var hookup: Hookup.State = .absent

    /// Les alertes à 80, 90 et 100 %.
    public var alerts: Bool {
        didSet { Shared.defaults.set(!alerts, forKey: "jauge.silence") }
    }

    /// Le relevé automatique (`Ping`) quand la ligne d'état se tait.
    public var autoRefresh: Bool {
        didSet { Shared.defaults.set(!autoRefresh, forKey: "jauge.sansReleve") }
    }

    public private(set) var refreshing = false

    /// Les seuils d'alerte, en pourcentage.
    static let thresholds: [Double] = [80, 90, 100]

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var resetTimer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var clock: Timer?

    private init() {
        alerts = !Shared.defaults.bool(forKey: "jauge.silence")
        autoRefresh = !Shared.defaults.bool(forKey: "jauge.sansReleve")
    }

    /// Lancé une fois, à l'ouverture de l'app qui héberge l'outil : les
    /// alertes doivent partir même panneau fermé.
    public func start() {
        guard !started else { return }
        started = true
        reload()
        watch()
        refreshHookup()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // Toutes les cinq minutes, une vérification qui ne coûte rien ; le
        // relevé, lui, ne part que si Claude sert et que le dernier date.
        let clock = Timer(timeInterval: 5 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { Jauge.shared.refreshIfStale(after: 10 * 60, onlyWhenActive: true) }
        }
        RunLoop.main.add(clock, forMode: .common)
        self.clock = clock
    }

    /// Demande un relevé si le dernier a plus de `age` secondes.
    public func refreshIfStale(after age: TimeInterval, onlyWhenActive: Bool) {
        guard autoRefresh, !refreshing else { return }
        if let usage, Date().timeIntervalSince(usage.updated) < age { return }
        refreshing = true
        Task {
            await Task.detached(priority: .utility) {
                if onlyWhenActive, !Ping.claudeIsActive() { return }
                _ = Ping.run()
            }.value
            refreshing = false
            reload()
        }
    }

    public func refreshHookup() {
        hookup = Hookup.state()
    }

    /// Branche Claude Code sur Jauge. L'exécutable est celui de Jauge.app :
    /// depuis Trousse, on va le chercher là où il est installé.
    public func connect() {
        guard let executable = Self.executable else { return }
        hookup = Hookup.install(executable: executable)
    }

    public static var executable: String? {
        if Bundle.main.bundleIdentifier == "local.jauge" { return Bundle.main.executablePath }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "local.jauge")?
            .appending(path: "Contents/MacOS/Jauge").path
    }

    // MARK: Relevés

    private func watch() {
        let folder = Usage.file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Le dossier, pas le fichier : l'écriture atomique remplace le
        // fichier, et une surveillance du fichier perdrait sa trace.
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { Jauge.shared.reload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func reload() {
        guard let fresh = Usage.load(), fresh != usage else { return }
        usage = fresh
        check(fresh)
        scheduleReset(fresh)
    }

    // MARK: Alertes

    private func check(_ usage: Usage) {
        if let session = usage.session, !session.isExpired() {
            alert(.session, session, full: usage.sessionFull())
        }
        if let week = usage.week, !week.isExpired() {
            alert(.week, week, full: nil)
        }
    }

    enum Kind: String { case session, week }

    /// Une alerte par seuil et par fenêtre : la fenêtre est désignée par son
    /// heure de remise à zéro, qui change à chaque nouvelle session.
    private func alert(_ kind: Kind, _ window: Usage.Window, full: Date?) {
        let key = "jauge.alerte.\(kind.rawValue).\(Int(window.resetsAt.timeIntervalSince1970))"
        let notified = Shared.defaults.double(forKey: key)
        guard let crossed = Self.thresholds.last(where: { window.used >= $0 }), crossed > notified else { return }
        Shared.defaults.set(crossed, forKey: key)
        guard alerts else { return }

        let name = kind == .session ? "Session" : "Semaine"
        let reset = Self.moment(window.resetsAt)
        let title: String
        var body: String
        if crossed >= 100 {
            title = "\(name) Claude épuisée"
            body = "Reprise \(reset)."
        } else {
            title = "\(name) Claude à \(Int(window.used.rounded())) %"
            body = "Remise à zéro \(reset)."
            if let full { body += " À ce rythme, pleine vers \(full.formatted(date: .omitted, time: .shortened))." }
        }
        notify(title, body)
    }

    /// Prévient quand une session qu'on avait vue presque pleine repart à zéro.
    private func scheduleReset(_ usage: Usage) {
        resetTimer?.invalidate()
        guard let session = usage.session, !session.isExpired(), session.used >= 80 else { return }
        let timer = Timer(fire: session.resetsAt, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard Jauge.shared.alerts else { return }
                Jauge.shared.notify("Session Claude remise à zéro", "Tu repars de 0 %.")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        resetTimer = timer
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Formats

    /// « à 18 h 40 », « demain à 9 h », « mardi à 9 h ».
    static func moment(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "à \(time)" }
        if calendar.isDateInTomorrow(date) { return "demain à \(time)" }
        let day = date.formatted(.dateTime.weekday(.wide))
        return "\(day) à \(time)"
    }

    /// « dans 2 h 10 », « dans 12 min », « dans 3 j ».
    static func remaining(until date: Date, from now: Date = .now) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds < 3600 { return "dans \(max(1, seconds / 60)) min" }
        if seconds < 86_400 {
            let hours = seconds / 3600, minutes = (seconds % 3600) / 60
            return minutes == 0 ? "dans \(hours) h" : "dans \(hours) h \(String(format: "%02d", minutes))"
        }
        return "dans \(seconds / 86_400) j"
    }
}
