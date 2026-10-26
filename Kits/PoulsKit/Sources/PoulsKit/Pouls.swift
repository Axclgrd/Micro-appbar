import Foundation
import Observation

/// Le moniteur : il sonde en tâche de fond et publie ce que le panneau affiche.
///
/// Même discipline que le moniteur thermique de FanControl, pour la même
/// raison : sur un outil qui se rafraîchit en continu, tout le coût est dans
/// le redessin, pas dans la mesure.
///
/// 1. **On ne publie que ce qui change à l'écran.** Une charge qui passe de
///    23,4 à 23,6 % s'affiche « 23 % » dans les deux cas : la réassigner
///    réveillerait SwiftUI pour rien. On compare donc les valeurs *arrondies*
///    comme elles seront lues.
/// 2. **Panneau fermé, on ne sonde que l'essentiel.** Le détail par
///    application coûte mille appels noyau ; personne ne les regarde quand le
///    panneau est fermé. Reste la charge globale, deux appels, pour la ligne
///    d'état et l'icône.
@MainActor
@Observable
public final class Pouls {

    public private(set) var cpu = CPULoad(user: 0, system: 0, cores: Sondes.cores)
    public private(set) var memory: MemoryUsage?
    public private(set) var disk: DiskUsage?
    public private(set) var network: NetworkRate = .zero

    /// Les consommateurs, déjà réduits à ce que le panneau peut montrer.
    public private(set) var apps: [AppUsage] = []
    /// La part de processeur qui n'appartient à aucune application lisible :
    /// les démons de root. Affichée telle quelle plutôt que passée sous
    /// silence — sinon les lignes ne font pas le total et le panneau ment.
    public private(set) var systemShare: Double = 0
    public private(set) var conseils: [Conseil] = []

    /// Les soixante dernières mesures de charge, pour la courbe. C'est une
    /// forme, pas une chronologie : les points relevés panneau fermé sont
    /// espacés de cinq secondes au lieu de deux.
    public private(set) var history: [Double] = []

    /// Vrai tant que le premier débit n'a pas pu être calculé : une charge se
    /// mesure entre deux relevés, et le dire vaut mieux qu'afficher zéro.
    public private(set) var warmingUp = true

    public var etat: EtatMachine {
        EtatMachine(cpu: cpu.total,
                    pression: memory?.pression ?? .normale,
                    swap: memory?.swapUsed ?? 0)
    }

    /// Afficher la charge à côté de l'icône de la barre des menus.
    ///
    /// Éteint par défaut : un chiffre qui bouge en permanence dans la barre
    /// attire l'œil toutes les dix secondes sans qu'on l'ait demandé. Qui le
    /// veut l'allume.
    public var badgeEnabled: Bool {
        didSet {
            guard badgeEnabled != oldValue else { return }
            UserDefaults.standard.set(badgeEnabled, forKey: Self.badgeKey)
        }
    }

    private static let badgeKey = "pouls.badge"

    public var panelVisible = false {
        didSet {
            guard panelVisible != oldValue else { return }
            // Relancer la boucle plutôt que déclencher un relevé de plus :
            // c'est la *cadence* qui doit changer tout de suite. Sans ça, le
            // panneau qui s'ouvre attendrait la fin d'un sommeil de dix
            // secondes avant son premier chiffre à jour.
            stop()
            start()
        }
    }

    /// Réactif quand on regarde, économe sinon.
    private var interval: Duration { panelVisible ? .seconds(2) : .seconds(5) }

    private var task: Task<Void, Never>?
    private let sampler = Sampler()

    public init() {
        badgeEnabled = UserDefaults.standard.bool(forKey: Self.badgeKey)
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshNow()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func refreshNow() async {
        let detailed = panelVisible
        let snapshot = await sampler.read(detailed: detailed)

        // La charge globale, toujours : c'est elle que lit l'icône.
        if !same(cpu, snapshot.cpu) { cpu = snapshot.cpu }
        if memory != snapshot.memory { memory = snapshot.memory }

        if history.count >= 60 { history.removeFirst(history.count - 59) }
        history.append(snapshot.cpu.total)

        guard detailed else { return }

        if disk != snapshot.disk { disk = snapshot.disk }
        if !same(network, snapshot.network) { network = snapshot.network }

        // Les process de root manquent à l'appel : on nomme le reste au lieu
        // de laisser un écart inexpliqué entre le total et la somme des lignes.
        let compte = snapshot.apps.reduce(0) { $0 + $1.cpu }
        let reste = max(0, snapshot.cpu.total - compte)
        if abs(reste - systemShare) > 0.005 { systemShare = reste }

        // Peut redevenir vrai : à la réouverture du panneau, le premier
        // relevé ne sert que de base et ne rend aucune liste.
        if warmingUp != snapshot.apps.isEmpty { warmingUp = snapshot.apps.isEmpty }
        let retenues = trim(snapshot.apps)
        if !same(apps, retenues) { apps = retenues }

        let avis = Conseils.pour(snapshot, apps: snapshot.apps)
        if avis != conseils { conseils = avis }
    }

    /// Le panneau ne montre que cinq lignes par critère : garder les huit
    /// premières de chacun suffit, et évite de faire diffuser à SwiftUI une
    /// liste de trois cents applications deux fois par seconde.
    private func trim(_ all: [AppUsage]) -> [AppUsage] {
        var kept: [String: AppUsage] = [:]
        for critere in Critere.allCases {
            for app in all.sorted(by: { rank($0, critere) > rank($1, critere) }).prefix(8) {
                kept[app.id] = app
            }
        }
        return kept.values.sorted { $0.cpu > $1.cpu }
    }

    private func rank(_ app: AppUsage, _ critere: Critere) -> Double {
        switch critere {
        case .cpu:     app.cpu
        case .memoire: Double(app.memory)
        case .disque:  app.disk
        }
    }

    // MARK: Égalité telle qu'elle s'affiche

    private func same(_ a: CPULoad, _ b: CPULoad) -> Bool {
        Int(a.total * 100) == Int(b.total * 100) && Int(a.user * 100) == Int(b.user * 100)
    }

    private func same(_ a: NetworkRate, _ b: NetworkRate) -> Bool {
        // Sous le kilo-octet par seconde, les deux s'écrivent « 0 o/s ».
        Int(a.down / 1024) == Int(b.down / 1024) && Int(a.up / 1024) == Int(b.up / 1024)
    }

    private func same(_ a: [AppUsage], _ b: [AppUsage]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            guard x.id == y.id,
                  Int(x.cpu * 1000) == Int(y.cpu * 1000),
                  x.memory / (8 << 20) == y.memory / (8 << 20),
                  Int(x.disk / 65536) == Int(y.disk / 65536)
            else { return false }
        }
        return true
    }
}

/// Détenteur des compteurs cumulés, isolé sur son propre acteur : les mille
/// appels `libproc` d'un relevé détaillé ne doivent jamais toucher le fil
/// principal.
private actor Sampler {
    private var probe = ProcessProbe()
    private var ticks: CPUTicks?
    private var interfaces: [String: (down: UInt32, up: UInt32)] = [:]
    private var stamp: Date?

    func read(detailed: Bool) -> Snapshot {
        let now = Date()
        let elapsed = stamp.map { now.timeIntervalSince($0) } ?? 0

        var load = CPULoad(user: 0, system: 0, cores: Sondes.cores)
        if let current = Sondes.cpuTicks() {
            if let previous = ticks { load = Sondes.cpuLoad(from: previous, to: current) }
            ticks = current
        }

        let courant = Sondes.interfaceBytes()
        let rate: NetworkRate = interfaces.isEmpty ? .zero
            : Sondes.rate(from: interfaces, to: courant, seconds: elapsed)
        interfaces = courant
        stamp = now

        return Snapshot(
            cpu: load,
            memory: Sondes.memory(),
            disk: detailed ? Sondes.disk() : nil,
            network: rate,
            apps: detailed ? (probe.sample() ?? []) : []
        )
    }
}
