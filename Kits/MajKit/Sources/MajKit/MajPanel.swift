import AppKit
import Commun
import SwiftUI

struct MajPanel: View {
    @Bindable var maj: Maj
    @State private var journalOuvert = false
    @State private var journal = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            EnTete(symbole: symbole, teinte: teinte, titre: titre, detail: detail)

            Groupe("Mise à jour automatique") {
                Picker("Mode", selection: $maj.mode) {
                    ForEach(Maj.Mode.allCases) { Text($0.libelle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(aideMode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if maj.notificationsRefusees && maj.mode != .desactive {
                Text("Les notifications de Trousse sont refusées : Réglages Système › Notifications › Trousse.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let probleme = maj.probleme {
                Text(probleme)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if maj.installation {
                HStack(spacing: Espace.s) {
                    ProgressView().controlSize(.small)
                    Text(maj.etape).font(.subheadline).foregroundStyle(.secondary)
                }
            } else if let apercu = maj.apercu {
                disponible(apercu)
            }

            if let r = maj.resultat, !maj.installation {
                bilan(r)
            }

            Groupe("Dépôt") {
                Ligne("Dossier", maj.depot?.chemin ?? "introuvable")
                    .help(maj.depot?.chemin ?? "")
                Ligne("Suivi", "\(Depot.remote)/\(Depot.branche)")
                if let date = maj.dernierControle {
                    Ligne("Dernier contrôle", date.formatted(date: .abbreviated, time: .shortened))
                }
                Button("Choisir le dépôt…") { choisir() }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }

            DisclosureGroup("Journal", isExpanded: $journalOuvert) {
                ScrollView {
                    Text(journal)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 110)
                Button("Ouvrir le fichier") { maj.ouvrirJournal() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .font(.subheadline)
            .onChange(of: journalOuvert) { _, ouvert in if ouvert { journal = Journal.lire() } }
            .onChange(of: maj.installation) { _, _ in if journalOuvert { journal = Journal.lire() } }

            PiedDePanneau {
                Button(maj.verification ? "Vérification…" : "Vérifier maintenant") {
                    Task { await maj.verifier(manuel: true) }
                }
                .buttonStyle(.borderless)
                .disabled(maj.occupe)
            }
        }
        .padding(Espace.panneau)
        .frame(width: 340)
    }

    // MARK: Pièces

    private func disponible(_ a: Maj.Apercu) -> some View {
        Groupe("Mise à jour disponible") {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.s) {
                    ForEach(a.commits) { c in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.sujet).font(.subheadline)
                            Text("\(c.auteur) · \(c.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 130)

            Divider()
            Text(a.apps.isEmpty
                 ? "Aucune app installée n'est concernée."
                 : "Sera reconstruit : \(a.apps.joined(separator: ", ")).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if a.ventilateurs {
                Text("FanControl change : à réinstaller à la main ensuite, avec ! ./fancontrole/install.sh (mot de passe admin, dans un vrai Terminal).")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Installer la mise à jour") {
                Task { await maj.installer() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(a.blocage != nil || maj.occupe)
        }
    }

    private func bilan(_ r: Resultat) -> some View {
        Groupe("Dernière installation") {
            Ligne(r.date.formatted(date: .abbreviated, time: .shortened),
                  r.reussi ? "réussie" : "échec")
            if !r.ok.isEmpty {
                Text("Reconstruit : \(r.ok.map(Impact.nom).joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !r.reussi {
                Text("Échec : \(r.echec.map(Impact.nom).joined(separator: ", ")). L'ancienne version reste en place ; aucune nouvelle tentative automatique.")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Text(r.erreurs.joined(separator: "\n"))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Réessayer") { Task { await maj.reessayer() } }
                    .disabled(maj.occupe)
            }
            if r.ventilateurs {
                Text("FanControl : à réinstaller à la main avec ! ./fancontrole/install.sh")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func choisir() {
        let panneau = NSOpenPanel()
        panneau.canChooseDirectories = true
        panneau.canChooseFiles = false
        panneau.prompt = "Choisir"
        panneau.message = "Le dossier Micro-app cloné depuis GitHub"
        if panneau.runModal() == .OK, let url = panneau.url { maj.choisirDepot(url) }
    }

    // MARK: Textes

    private var symbole: String {
        if maj.installation { return "arrow.triangle.2.circlepath.circle.fill" }
        if maj.probleme != nil { return "exclamationmark.triangle.fill" }
        if let a = maj.apercu, a.blocage == nil { return "arrow.down.circle.fill" }
        return maj.mode == .desactive ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill"
    }

    private var teinte: Color {
        if maj.installation { return .accentColor }
        if maj.probleme != nil { return .orange }
        if let a = maj.apercu, a.blocage == nil { return .accentColor }
        return maj.mode == .desactive ? .secondary : .green
    }

    private var titre: String {
        if maj.installation { return "Installation" }
        if let a = maj.apercu { return a.blocage == nil ? "Mise à jour disponible" : "Mise à jour bloquée" }
        if maj.verification { return "Vérification…" }
        return maj.mode == .desactive ? "Désactivée" : "À jour"
    }

    private var detail: String {
        if maj.installation { return "Ne ferme pas la session : Trousse redémarrera si elle est mise à jour." }
        if let a = maj.apercu {
            return a.blocage ?? "\(a.commits.count) commit(s) sur \(Depot.remote)/\(Depot.branche)."
        }
        if maj.mode == .desactive { return "Rien n'est vérifié tant que tu ne le demandes pas." }
        return "Contrôle toutes les heures et au lancement."
    }

    private var aideMode: String {
        switch maj.mode {
        case .desactive: return "Aucun contrôle automatique. « Vérifier maintenant » reste possible."
        case .prevenir: return "Contrôle toutes les heures, notifie, et attend ton accord pour installer."
        case .automatique: return "Récupère (fast-forward seulement) puis reconstruit les seules apps touchées. Jamais sur un dépôt modifié, jamais de push."
        }
    }
}
