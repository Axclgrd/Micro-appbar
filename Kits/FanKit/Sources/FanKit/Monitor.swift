import Commun
import Foundation
import Observation
import SMCKit

/// Instantané cohérent, produit hors du fil principal.
struct Snapshot: Sendable {
    let thermal: ThermalReading
    let fans: [FanState]
}

/// Sonde le SMC en tâche de fond et publie l'état pour l'interface.
///
/// Deux principes gouvernent cette classe, appris à la mesure : le profilage a
/// montré que **tout** le coût CPU était du redessin AppKit, pas les lectures
/// IOKit (invisibles dans le profil).
///
/// 1. On ne publie que ce qui *change à l'écran*. Réassigner une température de
///    55,3 → 55,4 °C notifie SwiftUI alors que le label affiche « 55 » dans les
///    deux cas ; AppKit enchaîne alors un cycle d'affichage complet, jusqu'au
///    recalcul des zones de suivi de la fenêtre. On compare donc la valeur
///    *arrondie* avant d'assigner.
///
/// 2. On ne tient à jour le détail que si le panneau est ouvert. Fermé,
///    personne ne lit `thermal` ni `fans` : les rafraîchir ne fait que
///    réveiller le moteur de rendu pour rien.
@MainActor
@Observable
final class Monitor {

    /// Température affichée dans la barre de menus, en degrés entiers.
    /// Propriété distincte et volontairement grossière : c'est la seule que lit
    /// le label, donc la seule qui peut déclencher son redessin.
    private(set) var hotspotDisplay: Int?

    /// Détail affiché dans le panneau. Mis à jour uniquement panneau ouvert.
    private(set) var thermal: ThermalReading?
    private(set) var fans: [FanState] = []
    private(set) var error: String?

    /// Renseigné par la vue du panneau à son apparition / disparition.
    var panelVisible = false {
        didSet {
            guard panelVisible, panelVisible != oldValue else { return }
            // À l'ouverture, ne pas attendre le prochain tour de boucle :
            // le panneau afficherait des valeurs vieilles de plusieurs secondes.
            Task { await refreshNow() }
        }
    }

    var verdict: ThermalVerdict? {
        thermal?.hotspot.map { ThermalVerdict(hotspot: $0) }
    }

    /// Cadence de sondage : réactif quand on regarde, économe sinon.
    private var interval: Duration { panelVisible ? .seconds(1) : .seconds(4) }

    private var task: Task<Void, Never>?
    private let reader: Reader?

    init() {
        do {
            reader = try Reader()
        } catch {
            reader = nil
            self.error = "\(error)"
        }
    }

    func start() {
        guard task == nil, reader != nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshNow()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func refreshNow() async {
        guard let reader else { return }
        guard let snapshot = await reader.read() else {
            if error == nil { error = "Lecture SMC impossible" }
            return
        }

        // Toujours : la valeur de la barre de menus, mais seulement si elle
        // change réellement d'affichage.
        let rounded = snapshot.thermal.hotspot.map { Int($0.rounded()) }
        if rounded != hotspotDisplay { hotspotDisplay = rounded }

        // Seulement panneau ouvert : le détail.
        if panelVisible {
            thermal = snapshot.thermal
            fans = snapshot.fans
        }
        if error != nil { error = nil }
    }

    /// Détenteur de la connexion SMC, isolé sur son propre acteur pour que les
    /// appels IOKit bloquants ne touchent jamais le main actor.
    private actor Reader {
        private let smc: SMC
        private let sensors: ThermalSensors
        private let controller: FanController

        init() throws {
            smc = try SMC()
            sensors = ThermalSensors(smc: smc)
            controller = try FanController(smc: smc)
        }

        func read() -> Snapshot? {
            Snapshot(thermal: sensors.read(), fans: controller.allStates())
        }
    }
}
