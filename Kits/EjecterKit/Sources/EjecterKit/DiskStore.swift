import Commun
import AppKit
import Observation

/// L'état affiché, et le seul endroit qui parle au main actor.
@MainActor
@Observable
final class DiskStore {

    private(set) var devices: [Device] = []
    /// Disques en cours d'éjection : le bouton doit se figer, pas clignoter.
    private(set) var busy: Set<String> = []
    /// Dernier retour par disque, succès comme échec.
    private(set) var report: [String: Outcome] = [:]
    /// Processus fautifs, calculés seulement après un échec.
    private(set) var blockers: [String: [Blocker]] = [:]

    /// Garder l'icône même sans disque branché. Réglable seulement quand un
    /// disque est là — sinon il n'y a pas de panneau pour le décocher.
    var alwaysVisible = Shared.defaults.bool(forKey: "alwaysVisible") {
        didSet { Shared.defaults.set(alwaysVisible, forKey: "alwaysVisible") }
    }

    /// Renseigné par le panneau : fermé, on cesse de sonder.
    var panelVisible = false {
        didSet {
            guard panelVisible, panelVisible != oldValue else { return }
            Task { await refresh() }
            startTicking()
        }
    }

    private let scanner = DeviceScanner()
    private let agent = DiskAgent()
    private var ticker: Task<Void, Never>?
    private var pending: Task<Void, Never>?

    init() {
        // Montage et démontage sont des événements : les guetter coûte moins
        // cher que de sonder, et réagit plus vite qu'aucune cadence.
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            }
        }
        Task { await refresh() }
    }

    // MARK: Lecture

    func refresh() async {
        let scanned = await scanner.scan()
        guard scanned != devices else { return }
        devices = scanned
        // Un disque disparu emporte ses messages avec lui.
        let ids = Set(scanned.map(\.id))
        report = report.filter { ids.contains($0.key) }
        blockers = blockers.filter { ids.contains($0.key) }
    }

    /// Les notifications de montage arrivent en rafale (un volume, puis son
    /// conteneur, puis ses instantanés). On laisse la rafale retomber.
    private func refreshSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.panelVisible else { return }
                await self.refresh()
            }
        }
    }

    // MARK: Actions

    func eject(_ device: Device) async {
        await perform(device) { await self.agent.eject(device.id) }
    }

    func forceEject(_ device: Device) async {
        await perform(device) { await self.agent.forceEject(device.id) }
    }

    func unmount(_ device: Device) async {
        await perform(device) { await self.agent.unmount(device.id) }
    }

    func mount(_ device: Device) async {
        await perform(device) { await self.agent.mount(device.id) }
    }

    private func perform(_ device: Device, _ action: () async -> Outcome) async {
        busy.insert(device.id)
        defer { busy.remove(device.id) }

        let mountPoints = device.mountedVolumes.compactMap(\.mountPoint)
        let outcome = await action()
        report[device.id] = outcome

        if outcome.ok {
            blockers[device.id] = nil
        } else {
            // La question qui suit un échec est toujours la même : « mais qui
            // le tient ? ». On y répond sans qu'on ait à le demander.
            blockers[device.id] = await agent.blockers(under: mountPoints)
        }
        await refresh()
    }

    /// Fermer un processus fautif. Une vraie app reçoit une demande de fermeture
    /// (elle peut proposer d'enregistrer) ; un processus sans interface reçoit
    /// un SIGTERM.
    func quit(_ blocker: Blocker, for device: Device) async {
        if let app = NSRunningApplication(processIdentifier: blocker.pid),
           app.bundleIdentifier != nil {
            app.terminate()
        } else {
            kill(blocker.pid, SIGTERM)
        }
        try? await Task.sleep(for: .milliseconds(700))
        blockers[device.id] = await agent.blockers(
            under: device.mountedVolumes.compactMap(\.mountPoint))
    }

    func dismiss(_ device: Device) {
        report[device.id] = nil
        blockers[device.id] = nil
    }
}
