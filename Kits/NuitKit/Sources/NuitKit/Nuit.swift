import AppKit
import Commun
import CoreAudio
import Foundation
import Observation

/// L'état du stabilisateur, côté interface.
///
/// Règles de sécurité (voir aussi `PriseSysteme`) :
/// - l'interrupteur n'est **pas** mémorisé : au lancement, rien n'est actif ;
/// - toute erreur, tout silence suspect, toute sortie de l'app détruit le tap ;
/// - un changement de sortie (AirPods…) détruit le tap, attend, puis reconstruit.
@MainActor
@Observable
final class Nuit {
    enum Etat: Equatable {
        case desactive
        case demarrage
        case actif
        /// Le tap tourne mais aucune app ne joue : rien à lisser.
        case enAttente
        case erreur(String)
    }

    enum Preset: String, CaseIterable, Identifiable {
        case nuit, doux
        var id: String { rawValue }
        var titre: String { self == .nuit ? "Nuit" : "Doux" }
        var aide: String {
            self == .nuit
            ? "Compression forte et niveau lissé : les explosions et le générique ne dépassent plus les dialogues."
            : "Compression légère, sans nivellement : on garde de la dynamique, on écrête seulement les pics."
        }
    }

    private(set) var etat: Etat = .desactive
    /// Phrase d'avertissement (autorisation, contenu protégé…), vide sinon.
    private(set) var avertissement = ""
    private(set) var sortie = "—"

    // Mesures affichées (dBFS ; −∞ affiché « — »).
    private(set) var niveauEntree: Float = -120
    private(set) var niveauSortie: Float = -120
    private(set) var reduction: Float = 0
    private(set) var latenceMs: Double = 0
    private(set) var latenceMaterielMs: Double = 0

    /// L'interrupteur. Jamais relu depuis les préférences.
    var actif = false {
        didSet {
            guard actif != oldValue, !bascule else { return }
            actif ? demarrer() : arreter(vers: .desactive)
        }
    }

    var preset: Preset {
        didSet { Shared.defaults.set(preset.rawValue, forKey: "nuit.preset"); appliquer() }
    }

    /// Niveau au-delà duquel on comprime, dBFS.
    var cible: Double {
        didSet { Shared.defaults.set(cible, forKey: "nuit.cible"); appliquer() }
    }

    /// Vrai quand c'est le code (et non l'utilisateur) qui replie l'interrupteur.
    private var bascule = false
    private let prise = PriseSysteme()
    private var veille: Task<Void, Never>?
    private var relance: Task<Void, Never>?
    private var mesure: Task<Void, Never>?
    private var silences = 0
    private var dernierAppel = 0
    private var arrets = 0
    private var observateur: NSObjectProtocol?
    private var exclusions: NSObjectProtocol?

    init() {
        let d = Shared.defaults
        preset = Preset(rawValue: d.string(forKey: "nuit.preset") ?? "") ?? .nuit
        cible = d.object(forKey: "nuit.cible") as? Double ?? -24
        prise.reglageCourant = reglage()
        prise.surChangementDePeripherique = { [weak self] in
            Task { @MainActor in self?.peripheriqueChange() }
        }
        // Quitter l'app : le tap doit disparaître avant le processus.
        observateur = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [prise] _ in
            prise.arreter()
        }
        // Le mélangeur reprend ou rend une application : la prise globale
        // doit l'exclure ou la recapter, sinon on l'entendrait en double.
        exclusions = NotificationCenter.default.addObserver(
            forName: CoordinationAudio.changement, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.exclusionsChangees() }
        }
    }

    isolated deinit {
        prise.arreter()
    }

    // MARK: - Réglages

    func reglage() -> Dynamique.Reglage {
        var r = Dynamique.Reglage()
        let t = Float(cible)
        r.seuil = t
        switch preset {
        case .nuit:
            r.ratio = 5; r.genou = 6; r.relache = 150
            r.plafond = min(-1, t + 8)
            r.nivelleur = true; r.cible = t - 8
        case .doux:
            r.ratio = 2.5; r.genou = 10; r.relache = 250
            r.plafond = min(-1, t + 14)
            r.nivelleur = false
        }
        return r
    }

    private func appliquer() { prise.reglageCourant = reglage() }

    // MARK: - Cycle de vie

    private func demarrer() {
        relance?.cancel()
        etat = .demarrage
        avertissement = ""
        silences = 0
        do {
            try prise.demarrer(exclus: CoordinationAudio.repris.map { AudioObjectID($0) })
            CoordinationAudio.nuitActive = true
            sortie = prise.nomSortie
            latenceMaterielMs = prise.latenceMaterielMs
            etat = .enAttente
            surveiller()
        } catch {
            arreter(vers: .erreur("\(error)"))
        }
    }

    /// Détruit le tap — le son d'origine revient — puis passe à `vers`.
    private func arreter(vers: Etat) {
        veille?.cancel(); veille = nil
        relance?.cancel(); relance = nil
        prise.arreter()
        CoordinationAudio.nuitActive = false
        etat = vers
        if actif {
            bascule = true
            actif = false
            bascule = false
        }
        if case .desactive = vers { avertissement = "" }
    }

    /// Bascule de sortie (AirPods connectés, haut-parleurs…) : on détruit tout
    /// tout de suite, on laisse le système se stabiliser, on reconstruit.
    private func peripheriqueChange() {
        guard actif, etat != .desactive else { return }
        veille?.cancel(); veille = nil
        prise.arreter()
        etat = .demarrage
        relance?.cancel()
        relance = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, self.actif else { return }
            self.arrets += 1
            self.demarrer()
        }
    }

    /// L'ensemble des processus repris par le mélangeur a changé. Le tap
    /// global ne se modifie pas en place : on le reconstruit, vite, sans
    /// l'attente qu'impose un changement de sortie.
    private func exclusionsChangees() {
        guard actif, prise.estActive else { return }
        relance?.cancel()
        relance = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.actif else { return }
            self.demarrer()
        }
    }

    /// Chien de garde, une fois par seconde, tant que le tap tourne.
    ///
    /// Un tap sans autorisation (ou sur du son protégé) ne signale aucune
    /// erreur : il livre des zéros, **et** coupe le son d'origine. Si quelqu'un
    /// joue (CoreAudio le sait) et que le tap ne reçoit rien pendant 3 s, on le
    /// détruit pour que l'utilisateur entende de nouveau son film.
    private func surveiller() {
        veille?.cancel()
        dernierAppel = prise.dynamique.appels
        var nonNuls = prise.dynamique.echantillonsNonNuls
        veille = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.actif else { return }
                let d = self.prise.dynamique
                let jouent = PriseSysteme.quelquUnJoue()
                let recu = d.echantillonsNonNuls != nonNuls
                let tourne = d.appels != self.dernierAppel
                nonNuls = d.echantillonsNonNuls
                self.dernierAppel = d.appels
                if !jouent {
                    self.silences = 0
                    self.etat = .enAttente
                } else if recu {
                    self.silences = 0
                    self.etat = .actif
                    self.avertissement = ""
                } else {
                    self.silences += 1
                    if self.silences >= 3 {
                        self.arreter(vers: .erreur(tourne
                            ? "Le tap ne reçoit que du silence alors qu'une app joue du son."
                            : "Le flux audio s'est arrêté."))
                        self.avertissement = tourne
                            ? "Aucun signal reçu : l'autorisation « Enregistrement audio du système » manque peut-être (Réglages Système › Confidentialité et sécurité), ou le contenu est protégé (DRM). Le son d'origine est rétabli."
                            : "Le flux audio s'est arrêté. Le son d'origine est rétabli."
                        return
                    }
                }
            }
        }
    }

    // MARK: - Mesures (panneau ouvert seulement)

    func activate() {
        mesure?.cancel()
        mesure = Task { [weak self] in
            while !Task.isCancelled {
                self?.rafraichir()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func idle() { mesure?.cancel(); mesure = nil }

    private func rafraichir() {
        guard prise.estActive else {
            niveauEntree = -120; niveauSortie = -120; reduction = 0
            return
        }
        let d = prise.dynamique
        func db(_ x: Float) -> Float { x > 1e-6 ? 20 * log10f(x) : -120 }
        niveauEntree = db(d.crêteEntree)
        niveauSortie = db(d.crêteSortie)
        reduction = d.reductionMax
        latenceMs = d.latenceMs
        d.remettreMesures()
    }

    var resume: String {
        switch etat {
        case .desactive, .demarrage: return ""
        case .enAttente: return "En attente"
        case .actif: return preset.titre
        case .erreur: return "Erreur"
        }
    }
}
