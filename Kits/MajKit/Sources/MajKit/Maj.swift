import AppKit
import Commun
import Foundation
import Observation

/// Mise à jour de la suite depuis GitHub (`origin/main`).
///
/// Désactivée par défaut. Trois modes : rien, prévenir, ou tout faire. Dans
/// tous les cas la règle est la même, et elle est étroite : fast-forward
/// uniquement, jamais sur un dépôt modifié, jamais de push, jamais de sudo.
@MainActor
@Observable
final class Maj {
    enum Mode: String, CaseIterable, Identifiable {
        case desactive, prevenir, automatique
        var id: String { rawValue }
        var libelle: String {
            switch self {
            case .desactive: return "Désactivé"
            case .prevenir: return "Prévenir"
            case .automatique: return "Automatique"
            }
        }
    }

    /// Ce qu'une mise à jour ferait.
    struct Apercu: Equatable {
        var commits: [Commit]
        var apps: [String]
        var ventilateurs: Bool
        var blocage: String?
        var distant: String
    }

    var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            Shared.defaults.set(mode.rawValue, forKey: "maj.mode")
            Journal.ecrire("Mode : \(mode.libelle)")
            if mode == .desactive {
                tache?.cancel()
                tache = nil
            } else {
                Task { await notifications.demander(); await actualiserNotifications() }
                planifier()
            }
        }
    }

    private(set) var depot: Depot?
    private(set) var verification = false
    private(set) var installation = false
    private(set) var etape = ""
    private(set) var dernierControle: Date?
    private(set) var apercu: Apercu?
    private(set) var probleme: String?
    private(set) var resultat: Resultat?
    private(set) var notificationsRefusees = false

    private let notifications = Notifications()
    private var tache: Task<Void, Never>?
    private var veille: Task<Void, Never>?

    /// Une heure : assez pour qu'une correction arrive vite, assez peu pour
    /// ne jamais peser sur le réseau ni sur GitHub.
    private static let intervalle: Duration = .seconds(3600)

    init() {
        let d = Shared.defaults
        mode = Mode(rawValue: d.string(forKey: "maj.mode") ?? "") ?? .desactive
        dernierControle = d.object(forKey: "maj.controle") as? Date
        depot = Depot.chercher(memorise: d.string(forKey: "maj.depot"))
        resultat = Resultat.lire()
        Journal.tronquer()
        if Verrou.actif {
            // Une construction est déjà en cours (Trousse vient d'être relancée
            // par elle) : on attend sa fin pour en lire le bilan.
            surveiller()
        } else {
            accuserReception()
        }
        if mode != .desactive { planifier() }
    }

    // MARK: Interrupteurs

    var occupe: Bool { verification || installation || Verrou.actif }

    var resume: String {
        if installation { return "Installation…" }
        if let apercu, apercu.blocage == nil { return "\(apercu.commits.count) nouveauté(s)" }
        if probleme != nil { return "Attention" }
        return mode == .desactive ? "Désactivée" : mode.libelle
    }

    func choisirDepot(_ url: URL) {
        guard Depot.valide(url) else {
            probleme = "« \(url.path) » n'est pas le dépôt Micro-app (il faut .git, install.sh et trousse/build.sh)."
            return
        }
        Shared.defaults.set(url.path, forKey: "maj.depot")
        depot = Depot(racine: url.standardizedFileURL)
        probleme = nil
        Journal.ecrire("Dépôt : \(url.path)")
    }

    func actualiserNotifications() async {
        notificationsRefusees = await notifications.refusees() ?? false
    }

    // MARK: Vérification

    private func planifier() {
        tache?.cancel()
        tache = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            while !Task.isCancelled {
                await self?.verifier(manuel: false)
                try? await Task.sleep(for: Self.intervalle)
            }
        }
    }

    private func trouverDepot() -> Depot? {
        if let d = depot, Depot.valide(d.racine) { return d }
        depot = Depot.chercher(memorise: Shared.defaults.string(forKey: "maj.depot"))
        if depot == nil {
            let disque = "Le dépôt Micro-app est introuvable (disque non monté, dossier déplacé ?). Désigne-le avec « Choisir le dépôt… »."
            if probleme != disque { Journal.ecrire(disque) }
            probleme = disque
        }
        return depot
    }

    /// Un `git fetch`, puis ce qu'il faut en conclure. En mode automatique ou
    /// prévenir, la suite suit ; en manuel, on s'arrête à l'aperçu.
    func verifier(manuel: Bool) async {
        guard !occupe, let depot = trouverDepot() else { return }
        verification = true
        probleme = nil
        var examen: Examen?
        do {
            try await depot.recuperer()
            let e = try await depot.examiner()
            examen = e
            dernierControle = Date()
            Shared.defaults.set(dernierControle, forKey: "maj.controle")
            apercu = e.derriere > 0 ? construireApercu(e, racine: depot.racine) : nil
            if e.derriere == 0, e.devant > 0 {
                probleme = "Le dépôt a \(e.devant) commit(s) local en avance sur \(Depot.remote)/\(Depot.branche) (rien n'est poussé, jamais)."
            }
        } catch {
            probleme = error.localizedDescription
            Journal.ecrire("Vérification : \(error.localizedDescription)")
        }
        verification = false

        guard !manuel, let examen, examen.derriere > 0, let apercu else { return }
        switch mode {
        case .desactive:
            break
        case .prevenir:
            notifierUneFois(examen.distant, "prevenir", "Mise à jour disponible",
                            "\(apercu.commits.count) nouveauté(s) pour \(apercu.apps.isEmpty ? "la suite" : apercu.apps.joined(separator: ", ")). Ouvre le panneau Mise à jour pour l'installer.")
        case .automatique:
            if let blocage = apercu.blocage {
                notifierUneFois(examen.distant, "blocage", "Mise à jour reportée", blocage)
            } else {
                await installer()
            }
        }
    }

    private func construireApercu(_ e: Examen, racine: URL) -> Apercu {
        let touchees = Impact.touchees(par: e.changes, racine: racine)
        let installees = Impact.installees(touchees)
        return Apercu(
            commits: e.commits,
            apps: installees.map(Impact.nom),
            ventilateurs: installees.contains("fancontrole"),
            blocage: e.blocage,
            distant: e.distant)
    }

    // MARK: Installation

    /// Récupère (fast-forward) puis reconstruit les seules apps touchées.
    /// Appelée depuis le bouton, ou par le mode automatique.
    func installer() async {
        await lancer(reessai: false)
    }

    /// Reconstruit ce qui avait échoué, sans rien récupérer de plus.
    func reessayer() async {
        await lancer(reessai: true)
    }

    private func lancer(reessai: Bool) async {
        guard !occupe, let depot = trouverDepot() else { return }
        installation = true
        probleme = nil
        etape = "Vérification du dépôt…"
        do {
            try await depot.recuperer()
            let e = try await depot.examiner()
            if let blocage = e.blocage {
                probleme = blocage
                Journal.ecrire("Refusé : \(blocage)")
                installation = false
                return
            }
            let echecs = (resultat?.echec ?? []).compactMap { nom in
                Impact.apps.first { $0.dossier == nom }?.dossier
            }
            if e.derriere == 0 && echecs.isEmpty {
                apercu = nil
                etape = ""
                installation = false
                return
            }
            // Un seul build à la fois : on prend le verrou avant de toucher au dépôt.
            guard Verrou.prendre() else {
                probleme = "Une construction est déjà en cours."
                installation = false
                return
            }
            if e.derriere > 0 && !reessai {
                etape = "Récupération (fast-forward)…"
                do { try await depot.avancer() } catch {
                    Verrou.liberer()
                    throw error
                }
                Journal.ecrire("Avancé \(e.local.prefix(7)) → \(e.distant.prefix(7)) (\(e.commits.count) commit(s))")
            }
            let touchees = e.derriere > 0 && !reessai
                ? Impact.touchees(par: e.changes, racine: depot.racine) : []
            let apps = Impact.installees(
                Impact.apps.map(\.dossier).filter { touchees.contains($0) || echecs.contains($0) })
            let ventilateurs = apps.contains("fancontrole")
            guard !apps.isEmpty else {
                Verrou.liberer()
                apercu = nil
                installation = false
                etape = ""
                Journal.ecrire("Rien à reconstruire.")
                notifications.poster("Mise à jour appliquée", "Aucune app installée n'est concernée.")
                return
            }
            etape = "Compilation : \(apps.map(Impact.nom).joined(separator: ", "))…"
            Journal.ecrire("Reconstruction de \(apps.joined(separator: ", "))")
            do {
                try Installateur.lancer(depot: depot, commit: e.distant, apps: apps, ventilateurs: ventilateurs)
            } catch {
                Verrou.liberer()
                throw ErreurMaj("Impossible de lancer la reconstruction : \(error.localizedDescription)")
            }
            apercu = nil
            surveiller()
        } catch {
            probleme = error.localizedDescription
            Journal.ecrire("Installation : \(error.localizedDescription)")
            installation = false
            etape = ""
        }
    }

    /// Attend la fin du script, quel que soit le processus qui l'a lancé.
    private func surveiller() {
        installation = true
        if etape.isEmpty { etape = "Reconstruction en cours…" }
        veille?.cancel()
        veille = Task { [weak self] in
            while Verrou.actif {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
            }
            self?.terminer()
        }
    }

    private func terminer() {
        installation = false
        etape = ""
        resultat = Resultat.lire()
        accuserReception()
    }

    /// Un bilan qu'on n'a pas encore annoncé : on le notifie une fois.
    private func accuserReception() {
        guard let r = resultat else { return }
        let vu = Shared.defaults.double(forKey: "maj.vu")
        guard r.date.timeIntervalSince1970 > vu else { return }
        Shared.defaults.set(r.date.timeIntervalSince1970, forKey: "maj.vu")
        if r.reussi {
            var corps = "Reconstruit : \(r.ok.map(Impact.nom).joined(separator: ", "))."
            if r.ventilateurs { corps += " FanControl : à réinstaller à la main avec ! ./fancontrole/install.sh" }
            notifications.poster("Mise à jour installée", corps)
        } else {
            let detail = r.erreurs.first ?? "voir le journal"
            notifications.poster("Mise à jour : échec de la compilation",
                                 "\(r.echec.map(Impact.nom).joined(separator: ", ")) : l'ancienne version reste en place. \(detail)")
        }
    }

    private func notifierUneFois(_ hash: String, _ genre: String, _ titre: String, _ corps: String) {
        let cle = "\(genre):\(hash)"
        guard Shared.defaults.string(forKey: "maj.notifie") != cle else { return }
        Shared.defaults.set(cle, forKey: "maj.notifie")
        notifications.poster(titre, corps, id: "maj.\(genre)")
    }

    func ouvrirJournal() {
        NSWorkspace.shared.open(Chemins.journal)
    }
}
