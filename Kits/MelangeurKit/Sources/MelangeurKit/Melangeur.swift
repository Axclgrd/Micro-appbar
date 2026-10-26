import AppKit
import Commun
import CoreAudio
import Foundation
import Observation

/// Le réglage d'une application, mémorisé d'un lancement à l'autre.
public struct ReglageSource: Codable, Equatable, Sendable {
    /// 0 à 2 : au-delà de 1, le son est amplifié puis limité.
    public var volume: Float = 1
    public var muet = false
    /// UID d'une sortie précise ; `nil` suit la sortie par défaut.
    public var sortie: String?

    public static let neutre = ReglageSource()

    /// Neutre, l'application joue d'elle-même : aucun tap, aucune latence.
    public var estNeutre: Bool { volume == 1 && !muet && sortie == nil }
}

public enum EtatTranche: Equatable, Sendable {
    case active
    /// Le tap ne reçoit rien alors que l'app joue : son protégé (DRM). Le son
    /// d'origine passe, au volume d'origine.
    case relachee
    case enAttente
    case erreur(String)
}

/// Le mélangeur : les périphériques, les applications, et ce qui les relie.
///
/// Deux principes :
///
/// 1. **Ne rien intercepter sans raison.** Une application au réglage
///    d'origine (100 %, sortie par défaut) joue d'elle-même. Le tap n'apparaît
///    qu'au moment où on la règle, et disparaît quand on la remet à 100 % :
///    pas de latence ajoutée, pas de processeur dépensé pour rien.
/// 2. **Le réglage suit l'application, pas la session.** Spotify à 40 % reste
///    à 40 % quand on le relance demain : les réglages sont mémorisés par
///    identifiant d'application et réappliqués dès qu'elle ouvre une session
///    audio, panneau fermé ou non.
@MainActor
@Observable
public final class Melangeur {

    // MARK: Périphériques

    public private(set) var peripheriques: [Peripherique] = []
    public private(set) var sortieID = CA.inconnu
    public private(set) var entreeID = CA.inconnu
    public private(set) var alertesID = CA.inconnu
    public private(set) var reglagesSortie: ReglagesPeripherique = .aucun
    public private(set) var reglagesEntree: ReglagesPeripherique = .aucun
    public private(set) var volumeAlertes: Double?

    public var sorties: [Peripherique] { peripheriques.filter(\.sortiePossible) }
    public var entrees: [Peripherique] { peripheriques.filter(\.entreePossible) }
    public var destinationsAlertes: [Peripherique] { peripheriques.filter(\.alertesPossible) }
    public var sortie: Peripherique? { peripheriques.first { $0.id == sortieID } }
    public var entree: Peripherique? { peripheriques.first { $0.id == entreeID } }
    public var alertes: Peripherique? { peripheriques.first { $0.id == alertesID } }

    // MARK: Sources

    public private(set) var sources: [SourceAudio] = []
    public private(set) var reglages: [String: ReglageSource]
    public private(set) var etats: [String: EtatTranche] = [:]
    public private(set) var autorisation: Autorisation
    public private(set) var nuitActive = false

    public var applications: [SourceAudio] { sources.filter { !$0.systeme } }
    public var services: [SourceAudio] { sources.filter(\.systeme) }
    public var quiEcoute: [SourceAudio] { sources.filter(\.ecoute) }
    public var quiJoue: [SourceAudio] { sources.filter(\.joue) }

    public func reglage(_ source: SourceAudio) -> ReglageSource {
        reglages[source.id] ?? .neutre
    }

    /// Le panneau est ouvert : on relit tout chaque seconde, pour que les
    /// touches de volume, un casque qu'on branche, une app qui se met à jouer
    /// se voient tout de suite.
    public var panelVisible = false {
        didSet {
            guard panelVisible != oldValue else { return }
            if panelVisible {
                volumeAlertes = Alertes.volume()
                rafraichissement = Task { [weak self] in
                    while !Task.isCancelled {
                        self?.relireTout()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            } else {
                rafraichissement?.cancel()
                rafraichissement = nil
            }
        }
    }

    // MARK: Interne

    private var tranches: [String: Tranche] = [:]
    private var veilles: [String: Veille] = [:]
    /// Ce que l'utilisateur fait glisser en ce moment : on ne détruit pas sa
    /// tranche quand le curseur passe par 100 %, et on ne relit pas le volume
    /// d'un périphérique qu'il est en train de régler.
    private var editionSource: String?
    private var editionPeripherique = false
    private var demandeEnCours = false

    private var rafraichissement: Task<Void, Never>?
    private var garde: Task<Void, Never>?
    private var ecouteurs: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []

    /// Ce que le chien de garde retient d'une tranche d'un tour à l'autre.
    private struct Veille {
        var jouait = false
        /// Le tap a-t-il livré du son depuis le début de cette lecture ? Un
        /// appel visio qui se tait trois secondes n'a rien de suspect ; une
        /// lecture qui n'a *jamais* rien livré, si.
        var aEuDuSon = false
        var nonNuls = 0
        var appels = 0
        var muets = 0
        var figes = 0
    }

    private static let cle = "melangeur.reglages"

    public init() {
        if let data = Shared.defaults.data(forKey: Self.cle),
           let lus = try? JSONDecoder().decode([String: ReglageSource].self, from: data) {
            reglages = lus
        } else {
            reglages = [:]
        }
        autorisation = AutorisationAudio.etat()

        relireTout()
        ecouter()
        // Réglages mémorisés : ils s'appliquent dès le lancement, panneau
        // fermé, pour les applications qui jouent déjà.
        synchroniserTout()

        // Quitter : les taps doivent disparaître avant le processus. Ils
        // disparaîtraient avec lui de toute façon (ils sont privés), mais
        // autant rendre le son d'origine tout de suite.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.toutArreter() }
        }
    }

    // MARK: - Lectures

    private func relireTout() {
        relirePeripheriques()
        relireSources()
        if CoordinationAudio.nuitActive != nuitActive { nuitActive = CoordinationAudio.nuitActive }
    }

    private func relirePeripheriques() {
        let liste = Peripheriques.tous()
        if liste != peripheriques { peripheriques = liste }
        let s = Peripheriques.defaut(.sortie), e = Peripheriques.defaut(.entree), a = Peripheriques.alertes()
        if s != sortieID { sortieID = s }
        if e != entreeID { entreeID = e }
        if a != alertesID { alertesID = a }
        guard !editionPeripherique else { return }
        let rs = Peripheriques.reglages(s, .sortie), re = Peripheriques.reglages(e, .entree)
        if rs != reglagesSortie { reglagesSortie = rs }
        if re != reglagesEntree { reglagesEntree = re }
    }

    private func relireSources() {
        let liste = Sources.lister()
        if liste != sources { sources = liste }
    }

    // MARK: - Écouteurs système

    /// Pas de sondage quand le panneau est fermé : CoreAudio prévient quand
    /// une app ouvre ou ferme sa session, quand un casque arrive, quand la
    /// sortie par défaut change. C'est tout ce qu'il faut pour réappliquer les
    /// réglages au bon moment.
    private func ecouter() {
        let selecteurs = [
            kAudioHardwarePropertyProcessObjectList,
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
        ]
        for selecteur in selecteurs {
            let bloc: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.changementSysteme(selecteur) }
            }
            var a = CA.adresse(selecteur)
            AudioObjectAddPropertyListenerBlock(CA.systeme, &a, .main, bloc)
            ecouteurs.append((selecteur, bloc))
        }
    }

    private func changementSysteme(_ selecteur: AudioObjectPropertySelector) {
        switch selecteur {
        case kAudioHardwarePropertyProcessObjectList:
            relireSources()
            synchroniserTout()
        case kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice:
            relirePeripheriques()
            // Une sortie a disparu, ou la sortie par défaut a changé : les
            // tranches qui la suivaient doivent la suivre encore.
            rerouter()
        default:
            relirePeripheriques()
        }
    }

    // MARK: - Actions : périphériques

    public func choisir(_ p: Peripherique, comme sens: Sens) {
        Peripheriques.choisir(p.id, sens)
        relirePeripheriques()
    }

    public func choisirAlertes(_ p: Peripherique) {
        Peripheriques.choisirAlertes(p.id)
        relirePeripheriques()
    }

    /// `fini` à faux pendant le glissement : la valeur part tout de suite au
    /// périphérique, mais on ne relit pas par-dessus la main de l'utilisateur.
    public func reglerVolume(_ v: Float, _ sens: Sens, fini: Bool) {
        let id = sens == .sortie ? sortieID : entreeID
        editionPeripherique = !fini
        Peripheriques.reglerVolume(id, sens, v)
        if sens == .sortie { reglagesSortie.volume = v } else { reglagesEntree.volume = v }
        // Monter le volume d'un périphérique coupé, c'est vouloir l'entendre.
        if v > 0, (sens == .sortie ? reglagesSortie.muet : reglagesEntree.muet) == true {
            basculerMuet(sens)
        }
    }

    public func basculerMuet(_ sens: Sens) {
        let id = sens == .sortie ? sortieID : entreeID
        let actuel = (sens == .sortie ? reglagesSortie.muet : reglagesEntree.muet) ?? false
        Peripheriques.reglerMuet(id, sens, !actuel)
        relirePeripheriques()
    }

    public func reglerBalance(_ v: Float, fini: Bool) {
        editionPeripherique = !fini
        // Le centre accroche : on y revient sans viser au pixel près.
        let valeur = abs(v - 0.5) < 0.04 ? 0.5 : v
        Peripheriques.reglerBalance(sortieID, valeur)
        reglagesSortie.balance = valeur
    }

    public func reglerDebit(_ debit: Double, _ sens: Sens) {
        Peripheriques.reglerDebit(sens == .sortie ? sortieID : entreeID, debit)
        relirePeripheriques()
    }

    public func reglerVolumeAlertes(_ v: Double, fini: Bool) {
        volumeAlertes = v
        if fini { Alertes.regler(v) }
    }

    // MARK: - Actions : applications

    public func reglerVolume(_ v: Float, de source: SourceAudio, fini: Bool) {
        // 100 % accroche : c'est la position « rendre la main à l'app », et le
        // curseur doit pouvoir y revenir sans précision chirurgicale.
        let valeur = abs(v - 1) < 0.04 ? 1 : v
        var r = reglage(source)
        r.volume = valeur
        if valeur > 0 { r.muet = false }
        editionSource = fini ? nil : source.id
        appliquer(r, a: source, enregistrer: fini)
    }

    public func basculerMuet(_ source: SourceAudio) {
        var r = reglage(source)
        r.muet.toggle()
        appliquer(r, a: source, enregistrer: true)
    }

    public func router(_ source: SourceAudio, vers uid: String?) {
        var r = reglage(source)
        r.sortie = uid
        appliquer(r, a: source, enregistrer: true)
    }

    public func remettre(_ source: SourceAudio) {
        appliquer(.neutre, a: source, enregistrer: true)
    }

    public func demanderAutorisation() {
        guard !demandeEnCours else { return }
        if autorisation == .refusee {
            AutorisationAudio.ouvrirReglages()
            return
        }
        demandeEnCours = true
        AutorisationAudio.demander { [weak self] _ in
            guard let self else { return }
            self.demandeEnCours = false
            self.autorisation = AutorisationAudio.etat()
            self.synchroniserTout()
        }
    }

    /// Après un passage dans Réglages Système, l'état a pu changer sans que
    /// rien ne nous prévienne : on le relit à chaque ouverture du panneau.
    public func relireAutorisation() {
        let etat = AutorisationAudio.etat()
        guard etat != autorisation else { return }
        autorisation = etat
        synchroniserTout()
    }

    private func appliquer(_ r: ReglageSource, a source: SourceAudio, enregistrer: Bool) {
        if r.estNeutre { reglages[source.id] = nil } else { reglages[source.id] = r }
        synchroniser(source)
        if enregistrer { sauver() }
    }

    private func sauver() {
        guard let data = try? JSONEncoder().encode(reglages) else { return }
        Shared.defaults.set(data, forKey: Self.cle)
    }

    // MARK: - Tranches

    private func synchroniserTout() {
        let presentes = Set(sources.map(\.id))
        for cle in tranches.keys where !presentes.contains(cle) {
            liberer(cle)
        }
        for source in sources where reglages[source.id] != nil || tranches[source.id] != nil {
            synchroniser(source)
        }
    }

    private func synchroniser(_ source: SourceAudio) {
        let r = reglage(source)
        guard !r.estNeutre || editionSource == source.id else {
            liberer(source.id)
            return
        }
        guard !source.processus.isEmpty else { return }

        switch autorisation {
        case .refusee:
            liberer(source.id)
            etats[source.id] = .erreur("Autorisation refusée")
            return
        case .inconnue:
            liberer(source.id)
            etats[source.id] = .enAttente
            demanderAutorisation()
            return
        case .accordee, .indisponible:
            break
        }

        let gain = r.muet ? 0 : r.volume
        let uid = destination(r)
        guard let uid else {
            etats[source.id] = .erreur("Aucune sortie")
            return
        }

        if let t = tranches[source.id] {
            t.commande.gain = gain
            t.changerProcessus(source.processus)
            if t.sortieUID != uid {
                do { try t.changerSortie(uid) } catch {
                    tranches[source.id] = nil
                    etats[source.id] = .erreur("\(error)")
                }
            }
        } else {
            do {
                let t = try Tranche(cle: source.id, nom: source.nom, processus: source.processus,
                                    sortieUID: uid, gain: gain)
                t.surChangementDeDebit = { [weak self] in
                    Task { @MainActor in self?.reconstruire(source.id) }
                }
                tranches[source.id] = t
                veilles[source.id] = Veille()
                etats[source.id] = .active
            } catch {
                etats[source.id] = .erreur("\(error)")
            }
        }
        declarer()
        surveiller()
    }

    /// La sortie d'une tranche : celle qu'on a choisie si elle est encore là,
    /// la sortie par défaut sinon. Un casque débranché ne rend pas l'app muette.
    private func destination(_ r: ReglageSource) -> String? {
        if let voulue = r.sortie, peripheriques.contains(where: { $0.uid == voulue && $0.canauxSortie > 0 }) {
            return voulue
        }
        return Peripheriques.uid(Peripheriques.defaut(.sortie))
    }

    private func rerouter() {
        for (cle, t) in tranches {
            let r = reglages[cle] ?? .neutre
            guard let uid = destination(r), uid != t.sortieUID else { continue }
            do { try t.changerSortie(uid) } catch {
                tranches[cle] = nil
                etats[cle] = .erreur("\(error)")
            }
        }
        declarer()
    }

    private func reconstruire(_ cle: String) {
        guard let t = tranches[cle] else { return }
        do { try t.changerSortie(t.sortieUID) } catch {
            tranches[cle] = nil
            etats[cle] = .erreur("\(error)")
            declarer()
        }
    }

    private func liberer(_ cle: String) {
        if let t = tranches.removeValue(forKey: cle) {
            t.arreter()
            declarer()
        }
        veilles[cle] = nil
        etats[cle] = nil
    }

    private func toutArreter() {
        for t in tranches.values { t.arreter() }
        tranches.removeAll()
        declarer()
    }

    /// Nuit doit savoir quels processus on rejoue, pour ne pas les rejouer
    /// une seconde fois. Voir `CoordinationAudio`.
    private func declarer() {
        CoordinationAudio.declarer(Set(tranches.values.flatMap(\.processus)))
    }

    // MARK: - Chien de garde

    /// Deux fois par seconde, tant qu'une tranche existe.
    ///
    /// Il guette deux pannes qui ne lèvent aucune erreur :
    ///
    /// - **Le tap ne livre que des zéros** alors que l'app joue, et n'a
    ///   jamais rien livré depuis le début de la lecture : son protégé. On
    ///   relâche la tranche — l'app joue à son volume d'origine plutôt que pas
    ///   du tout — et on la reprend dès que du son arrive.
    /// - **L'IOProc ne tourne plus** (sortie disparue sous nos pieds) : on
    ///   reconstruit. `.mutedWhenTapped` a déjà rendu le son d'origine entre-temps.
    private func surveiller() {
        guard garde == nil, !tranches.isEmpty else { return }
        garde = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !self.tranches.isEmpty else {
                    self?.garde = nil
                    return
                }
                self.ronde()
            }
        }
    }

    private func ronde() {
        for (cle, t) in tranches {
            var v = veilles[cle] ?? Veille()
            let jouent = t.processus.contains {
                (CA.lire($0, kAudioProcessPropertyIsRunningOutput) as UInt32? ?? 0) != 0
            }
            if jouent && !v.jouait { v.aEuDuSon = false; v.muets = 0 }
            v.jouait = jouent

            let recu = t.commande.nonNuls != v.nonNuls
            v.nonNuls = t.commande.nonNuls
            let tourne = t.commande.appels != v.appels
            v.appels = t.commande.appels

            if recu {
                v.aEuDuSon = true
                v.muets = 0
                if t.relachee {
                    t.relacher(false)
                    etats[cle] = .active
                }
            } else if jouent, !v.aEuDuSon, !t.relachee {
                v.muets += 1
                if v.muets >= 6 {
                    t.relacher(true)
                    etats[cle] = .relachee
                }
            }

            v.figes = tourne ? 0 : v.figes + 1
            veilles[cle] = v
            if v.figes >= 4 {
                veilles[cle]?.figes = 0
                reconstruire(cle)
            }
        }
    }

    // MARK: - Résumé

    public var resume: String {
        var parties: [String] = []
        if let v = reglagesSortie.volume {
            parties.append(reglagesSortie.muet == true ? "coupé" : "\(Int((v * 100).rounded())) %")
        }
        let n = quiJoue.filter { !$0.systeme }.count
        if n > 0 { parties.append(n > 1 ? "\(n) jouent" : "1 joue") }
        return parties.joined(separator: " · ")
    }
}
