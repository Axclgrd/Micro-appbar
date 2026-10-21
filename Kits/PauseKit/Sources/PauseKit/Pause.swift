import Commun
import Foundation
import Observation

/// La machine à états : micro libre → micro actif (musique mise en pause ou
/// non) → micro libre depuis `delai` → reprise.
///
/// Garde-fous, tous pour la même raison (ne jamais lancer de musique que
/// personne n'a demandée) : on ne reprend que si c'est nous qui avons mis en
/// pause, que Music est toujours en pause, et sur le même morceau.
@MainActor
@Observable
final class Pause {
    enum Etat: Equatable {
        case enVeille
        case microActif
        case musiqueEnPause
        case desactive
    }

    private(set) var etat: Etat = .desactive
    private(set) var entree = "—"
    private(set) var autorisationRefusee = false

    var actif: Bool {
        didSet {
            guard actif != oldValue else { return }
            Shared.defaults.set(actif, forKey: "pause.actif")
            actif ? demarrer() : arreter()
        }
    }

    /// Reprendre la lecture quand le micro se libère.
    var reprise: Bool {
        didSet { Shared.defaults.set(reprise, forKey: "pause.reprise") }
    }

    /// Ne réagir qu'à une entrée Bluetooth (AirPods…). Le micro du Mac Studio
    /// n'existe pas ; un micro USB, lui, ne dégrade pas le son de sortie.
    var seulementBluetooth: Bool {
        didSet {
            Shared.defaults.set(seulementBluetooth, forKey: "pause.bluetooth")
            if monitor != nil { traiter(dernier) }
        }
    }

    private let lecteur: Lecteur
    private let delai: Duration
    private var monitor: MicMonitor?
    private var dernier = EtatMicro(actif: false, bluetooth: false, nom: "—")
    private var morceau: String?
    private var attente: Task<Void, Never>?

    init(lecteur: Lecteur = LecteurMusic(), delai: Duration = .seconds(1), surveiller: Bool = true) {
        self.lecteur = lecteur
        self.delai = delai
        let d = Shared.defaults
        actif = d.object(forKey: "pause.actif") as? Bool ?? true
        reprise = d.object(forKey: "pause.reprise") as? Bool ?? true
        seulementBluetooth = d.object(forKey: "pause.bluetooth") as? Bool ?? true
        if actif && surveiller { demarrer() }
    }

    private func demarrer() {
        etat = .enVeille
        let m = MicMonitor { [weak self] e in self?.traiter(e) }
        monitor = m
        m.start()
    }

    private func arreter() {
        monitor?.stop()
        monitor = nil
        attente?.cancel()
        // Éteindre l'interrupteur pendant une pause ne doit pas laisser la
        // musique coupée sans que rien ne la rende : on la reprend.
        if morceau != nil, reprise { _ = reprendreSiPossible() }
        morceau = nil
        etat = .desactive
    }

    /// Point d'entrée unique, appelé par CoreAudio et par les tests.
    func traiter(_ e: EtatMicro) {
        dernier = e
        entree = e.nom
        guard actif else { return }
        let occupe = e.actif && (e.bluetooth || !seulementBluetooth)
        occupe ? microOccupe() : microLibre()
    }

    private func microOccupe() {
        attente?.cancel()          // un appui de plus sur Espace : on annule la reprise
        attente = nil
        if etat == .musiqueEnPause { return }
        etat = .microActif
        switch lecteur.mettreEnPause() {
        case .pause(let id):
            morceau = id
            etat = .musiqueEnPause
            autorisationRefusee = false
        case .refuse:
            autorisationRefusee = true
        case .rien:
            break
        }
    }

    private func microLibre() {
        guard etat != .enVeille else { return }
        attente?.cancel()
        attente = Task { [weak self, delai] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled else { return }
            self?.terminerAttente()
        }
    }

    private func terminerAttente() {
        if etat == .musiqueEnPause, reprise { _ = reprendreSiPossible() }
        morceau = nil
        etat = .enVeille
    }

    private func reprendreSiPossible() -> Bool {
        guard let morceau else { return false }
        return lecteur.reprendre(morceau: morceau)
    }

    /// Attend la fin du délai de reprise — utile aux tests.
    func attendre() async { await attente?.value }

    var resume: String {
        switch etat {
        case .desactive: return ""
        case .enVeille: return ""
        case .microActif: return "Micro actif"
        case .musiqueEnPause: return "Musique en pause"
        }
    }
}
