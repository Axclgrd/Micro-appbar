import AppKit
import Commun
import IOKit.pwr_mgt
import Observation

/// Ce qui maintient la machine éveillée, et jusqu'à quand.
@MainActor
@Observable
final class Awake {

    /// Pourquoi on empêche la veille. C'est la raison qui décide de la fin :
    /// une durée s'épuise, une app se ferme, « sans limite » attend un clic.
    enum Reason: Equatable {
        case idle
        case until(Date)
        case indefinite
        case app(bundleID: String, name: String)
    }

    private(set) var reason: Reason = .idle

    /// Empêcher l'écran de s'éteindre, ou seulement la mise en veille système.
    ///
    /// La distinction compte : pour un long build ou un téléchargement, garder
    /// l'écran allumé ne sert qu'à user la dalle. Pour une lecture ou une
    /// présentation, c'est tout l'inverse.
    var keepDisplayOn = false {
        didSet {
            Shared.defaults.set(keepDisplayOn, forKey: "keepDisplayOn")
            guard isActive, keepDisplayOn != oldValue else { return }
            // L'assertion porte son type dans sa création : on la refait.
            releaseAssertion()
            createAssertion()
        }
    }

    var isActive: Bool { reason != .idle }

    /// Minutes restantes, arrondies. Propriété volontairement grossière : c'est
    /// la seule que lit l'étiquette de la barre de menus, donc la seule qui
    /// puisse déclencher son redessin.
    private(set) var minutesLeft: Int?

    private var assertion: IOPMAssertionID = 0
    private var ticker: Task<Void, Never>?

    init() {
        keepDisplayOn = Shared.defaults.bool(forKey: "keepDisplayOn")

        // Une app surveillée qui se ferme rend la main tout de suite : attendre
        // le prochain tour d'horloge laisserait la machine éveillée pour rien.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            // L'identifiant est extrait ici : une `Notification` n'est pas
            // transmissible entre contextes d'isolation, une chaîne l'est.
            let terminated = (note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, case .app(let watched, _) = self.reason,
                      watched == terminated else { return }
                self.stop()
            }
        }
    }

    // MARK: Commandes

    func start(_ reason: Reason) {
        guard reason != .idle else { return stop() }
        if !isActive { createAssertion() }
        self.reason = reason
        refreshCountdown()
        startTicking()
    }

    func extend(by seconds: TimeInterval) {
        let base: Date
        if case .until(let deadline) = reason, deadline > .now {
            base = deadline
        } else {
            base = .now
        }
        start(.until(base.addingTimeInterval(seconds)))
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        releaseAssertion()
        reason = .idle
        minutesLeft = nil
    }

    // MARK: Affichage

    var deadline: Date? {
        if case .until(let date) = reason { return date }
        return nil
    }

    var watchedApp: String? {
        if case .app(_, let name) = reason { return name }
        return nil
    }

    /// Ce qu'on écrit dans le panneau, en une ligne.
    var summary: String {
        switch reason {
        case .idle:
            return "La machine s'endort normalement."
        case .indefinite:
            return keepDisplayOn
                ? "Éveillée sans limite, écran compris."
                : "Éveillée sans limite. L'écran peut s'éteindre."
        case .until(let date):
            return "Éveillée jusqu'à \(date.formatted(date: .omitted, time: .shortened))."
        case .app(_, let name):
            return "Éveillée tant que \(name) tourne."
        }
    }

    // MARK: Interne

    private func startTicking() {
        ticker?.cancel()
        // Vingt secondes : assez fin pour que l'échéance tombe juste, assez
        // large pour ne rien coûter. L'étiquette, elle, ne change qu'à la
        // minute.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, self.isActive else { return }
                if let deadline = self.deadline, deadline <= .now {
                    self.stop()
                    return
                }
                self.refreshCountdown()
            }
        }
    }

    private func refreshCountdown() {
        guard let deadline else {
            if minutesLeft != nil { minutesLeft = nil }
            return
        }
        let minutes = max(0, Int((deadline.timeIntervalSinceNow / 60).rounded(.up)))
        if minutes != minutesLeft { minutesLeft = minutes }
    }

    /// L'assertion d'alimentation : la même que celle posée par `caffeinate`,
    /// donc visible dans `pmset -g assertions` et comptée par le système comme
    /// n'importe quelle autre.
    private func createAssertion() {
        let type = keepDisplayOn
            ? kIOPMAssertionTypeNoDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        var identifier: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Éveil : session maintenue par l'utilisateur" as CFString,
            &identifier
        )
        assertion = status == kIOReturnSuccess ? identifier : 0
    }

    private func releaseAssertion() {
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
    }
}
