import AppKit
import Commun
import CoreAudio
import SwiftUI

struct MelangeurPanel: View {
    @Bindable var melangeur: Melangeur
    @State private var servicesVisibles = false
    @State private var autresVisibles = false
    @Environment(\.accessibilityReduceMotion) private var reduireMouvement

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            header
            // Hauteur fixe, pas un plafond : leçon de Pouls. Avec un simple
            // `maxHeight`, le popover ne tire de la vue aucune hauteur et
            // s'ouvre à 320 pt. Ici, à peu près la moitié du contenu, le reste
            // défile.
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    sortie
                    applications
                    entree
                    alertes
                }
                .padding(.bottom, 2)
            }
            .frame(height: 440)
            footer
        }
        .padding(Espace.panneau)
        .onAppear { melangeur.relireAutorisation() }
    }

    // MARK: En-tête

    private var header: some View {
        EnTete(symbole: symboleVolume(melangeur.reglagesSortie.volume, muet: melangeur.reglagesSortie.muet ?? false),
               titre: titre,
               detail: detail) {
            if let v = melangeur.reglagesSortie.volume {
                Text(melangeur.reglagesSortie.muet == true ? "Coupé" : pourcent(v))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    /// Le nom de la sortie est déjà juste en dessous : l'en-tête dit ce
    /// qu'on ne lit nulle part ailleurs — qui joue, et ce que le mélangeur
    /// intercepte.
    private var titre: String {
        let jouent = melangeur.quiJoue.filter { !$0.systeme }
        switch jouent.count {
        case 0: return "Silence"
        case 1: return "\(jouent[0].nom) joue"
        default: return "\(jouent.count) applications jouent"
        }
    }

    private var detail: String {
        switch melangeur.reglages.count {
        case 0: return "Aucune application réglée : chacune joue à son volume d'origine."
        case 1: return "1 application réglée par le mélangeur."
        default: return "\(melangeur.reglages.count) applications réglées par le mélangeur."
        }
    }

    // MARK: Sortie

    private var sortie: some View {
        Groupe("Sortie") {
            menuPeripherique(melangeur.sorties, actuel: melangeur.sortieID, sens: .sortie) {
                melangeur.choisir($0, comme: .sortie)
            }

            let r = melangeur.reglagesSortie
            if let v = r.volume {
                curseur(valeur: v, plage: 0...1, muet: r.muet ?? false, libelle: "Volume de sortie",
                        regler: { melangeur.reglerVolume($0, .sortie, fini: $1) },
                        couper: r.muet == nil ? nil : { melangeur.basculerMuet(.sortie) })
            } else {
                // Les écrans HDMI et DisplayPort ne laissent pas macOS régler
                // leur volume : c'est vrai dans Réglages Système aussi. On le
                // dit plutôt que de montrer un curseur mort.
                Text("Cet appareil règle son volume lui-même, avec ses propres boutons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let b = r.balance {
                HStack(spacing: Espace.s) {
                    Text("G").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(b) },
                                          set: { melangeur.reglerBalance(Float($0), fini: false) }),
                           in: 0...1,
                           onEditingChanged: { if !$0 { melangeur.reglerBalance(melangeur.reglagesSortie.balance ?? 0.5, fini: true) } })
                        .controlSize(.mini)
                        .accessibilityLabel("Balance")
                    Text("D").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                .help("Balance gauche–droite")
            }

            if r.debits.count > 1 {
                menuDebit(r, sens: .sortie)
            }
        }
    }

    // MARK: Applications

    private var applications: some View {
        Groupe("Applications") {
            autorisationBandeau

            if melangeur.nuitActive, !melangeur.reglages.isEmpty {
                Label("Le mode nuit ne s'applique pas aux applications réglées ici.",
                      systemImage: "moon.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Au premier plan : ce qui joue, et ce qu'on a réglé. Le reste —
            // toutes les apps qui ont ouvert une session audio un jour — se
            // déplie. Sans ce tri, treize applications et dix-sept services
            // repoussaient l'entrée et les alertes hors de vue.
            let (enAvant, autres) = repartir(melangeur.applications)

            if enAvant.isEmpty {
                Text(autres.isEmpty
                     ? "Aucune application n'a ouvert de session audio."
                     : "Aucune application ne joue en ce moment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Espace.xs)
            }

            ForEach(enAvant) { source in
                rangee(source)
                if source.id != enAvant.last?.id { Divider() }
            }

            if melangeur.applications.contains(where: \.navigateur) {
                // L'honnêteté d'abord : macOS ne sépare pas les onglets.
                Text("Un navigateur fait jouer tous ses onglets par un seul processus audio : ses sites se règlent ensemble.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !autres.isEmpty {
                Divider()
                depliant("Autres applications", autres.count, ouvert: $autresVisibles)
                if autresVisibles {
                    ForEach(autres) { rangee($0) }
                }
            }

            if !melangeur.services.isEmpty {
                Divider()
                depliant("Services du système", melangeur.services.count, ouvert: $servicesVisibles)
                if servicesVisibles {
                    ForEach(melangeur.services) { rangee($0) }
                }
            }
        }
    }

    /// Ce qui mérite d'être vu sans rien déplier : une app qui joue, une app
    /// qu'on a réglée (même silencieuse : on veut retrouver son curseur), une
    /// app en difficulté.
    private func repartir(_ liste: [SourceAudio]) -> ([SourceAudio], [SourceAudio]) {
        var enAvant: [SourceAudio] = [], autres: [SourceAudio] = []
        for s in liste {
            if s.joue || melangeur.reglages[s.id] != nil || melangeur.etats[s.id] != nil {
                enAvant.append(s)
            } else {
                autres.append(s)
            }
        }
        return (enAvant, autres)
    }

    private func depliant(_ titre: String, _ nombre: Int, ouvert: Binding<Bool>) -> some View {
        Button {
            withAnimation(reduireMouvement ? nil : .snappy(duration: 0.2)) {
                ouvert.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Text(titre)
                Text("\(nombre)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(ouvert.wrappedValue ? 90 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(ouvert.wrappedValue ? "Affichés" : "Masqués")
    }

    @ViewBuilder
    private var autorisationBandeau: some View {
        switch melangeur.autorisation {
        case .inconnue, .refusee:
            let refusee = melangeur.autorisation == .refusee
            HStack(alignment: .top, spacing: Espace.s) {
                Image(systemName: refusee ? "lock.fill" : "lock.open")
                    .foregroundStyle(refusee ? .orange : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Espace.xs) {
                    Text(refusee
                         ? "L'enregistrement audio du système est refusé : le volume de chaque application ne peut pas être réglé."
                         : "Régler une application à part demande l'autorisation « Enregistrement audio du système ».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(refusee ? "Ouvrir les réglages" : "Autoriser") {
                        melangeur.demanderAutorisation()
                    }
                    .controlSize(.small)
                }
            }
            .padding(Espace.s)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7))
        case .accordee, .indisponible:
            EmptyView()
        }
    }

    private func rangee(_ source: SourceAudio) -> some View {
        let r = melangeur.reglage(source)
        let etat = melangeur.etats[source.id]
        let bloque = melangeur.autorisation == .refusee

        return VStack(alignment: .leading, spacing: Espace.xs) {
            HStack(spacing: Espace.s) {
                Icone(bundlePath: source.bundlePath, repli: source.id == "simulateur" ? "iphone" : "gearshape.2")
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(source.nom)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if source.joue {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .symbolEffect(.variableColor.iterative, isActive: !reduireMouvement)
                                .accessibilityLabel("Joue du son")
                        }
                        if source.ecoute {
                            Image(systemName: "mic.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Utilise le micro")
                        }
                    }
                    if let (texte, couleur) = sousTitre(source, r, etat) {
                        Text(texte)
                            .font(.caption)
                            .foregroundStyle(couleur)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Espace.xs)
                menuSource(source, r)
            }

            curseur(valeur: r.volume, plage: 0...2, muet: r.muet, libelle: "Volume de \(source.nom)",
                    course: Course.console,
                    regler: { melangeur.reglerVolume($0, de: source, fini: $1) },
                    couper: { melangeur.basculerMuet(source) })
                .disabled(bloque)
        }
        .padding(.vertical, 2)
    }

    private func sousTitre(_ s: SourceAudio, _ r: ReglageSource, _ etat: EtatTranche?) -> (String, Color)? {
        switch etat {
        case .erreur(let message):
            return ("Réglage impossible : \(message)", .red)
        case .relachee:
            return ("Aucun son capté (contenu protégé ?) : il joue à son volume d'origine.", .orange)
        case .enAttente:
            return ("En attente de l'autorisation…", .secondary)
        default:
            break
        }
        var parties: [String] = []
        if let uid = r.sortie, let p = melangeur.peripheriques.first(where: { $0.uid == uid }) {
            parties.append("→ \(p.nom)")
        }
        if s.navigateur { parties.append("tous les onglets") }
        if r.volume > 1, !r.muet { parties.append("amplifié") }
        return parties.isEmpty ? nil : (parties.joined(separator: " · ").capitalisee, .secondary)
    }

    private func menuSource(_ source: SourceAudio, _ r: ReglageSource) -> some View {
        Menu {
            Picker("Sortie", selection: Binding(get: { r.sortie },
                                                set: { melangeur.router(source, vers: $0) })) {
                Text("Sortie par défaut").tag(String?.none)
                ForEach(melangeur.sorties) { p in
                    Label(p.nom, systemImage: p.symbole(.sortie)).tag(Optional(p.uid))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Rétablir le réglage d'origine") { melangeur.remettre(source) }
                .disabled(r.estNeutre)
        } label: {
            Image(systemName: r.sortie == nil ? "ellipsis.circle" : "arrow.triangle.branch")
                .foregroundStyle(r.sortie == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sortie de \(source.nom)")
        .accessibilityLabel("Options de \(source.nom)")
    }

    // MARK: Entrée

    private var entree: some View {
        Groupe("Entrée") {
            menuPeripherique(melangeur.entrees, actuel: melangeur.entreeID, sens: .entree) {
                melangeur.choisir($0, comme: .entree)
            }
            let r = melangeur.reglagesEntree
            if let v = r.volume {
                curseur(valeur: v, plage: 0...1, muet: r.muet ?? false, libelle: "Volume d'entrée",
                        symboles: ("mic.slash.fill", "mic.fill"),
                        regler: { melangeur.reglerVolume($0, .entree, fini: $1) },
                        couper: r.muet == nil ? nil : { melangeur.basculerMuet(.entree) })
            }
            let ecoutent = melangeur.quiEcoute.map(\.nom)
            Ligne("Utilisée par", ecoutent.isEmpty ? "personne" : ecoutent.joined(separator: ", "))
            if r.debits.count > 1 {
                menuDebit(r, sens: .entree)
            }
        }
    }

    // MARK: Alertes

    private var alertes: some View {
        Groupe("Alertes") {
            menuPeripherique(melangeur.destinationsAlertes, actuel: melangeur.alertesID, sens: .sortie) {
                melangeur.choisirAlertes($0)
            }
            if let v = melangeur.volumeAlertes {
                curseur(valeur: Float(v), plage: 0...1, muet: false, libelle: "Volume des alertes",
                        symboles: ("bell.slash", "bell"),
                        regler: { melangeur.reglerVolumeAlertes(Double($0), fini: $1) },
                        couper: nil)
            }
        }
    }

    // MARK: Pied

    private var footer: some View {
        PiedDePanneau {
            Button("Réglages Son…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Ouvrir les réglages Son de macOS")
        }
    }

    // MARK: Pièces

    /// Le choix d'un périphérique : son dessin, son nom, sa nature, et la
    /// liste du système derrière un menu à coches.
    private func menuPeripherique(_ liste: [Peripherique], actuel: AudioObjectID, sens: Sens,
                                  choisir: @escaping (Peripherique) -> Void) -> some View {
        let courant = liste.first { $0.id == actuel }
        return Menu {
            Picker("Périphérique", selection: Binding(get: { actuel },
                                                      set: { id in liste.first { $0.id == id }.map(choisir) })) {
                ForEach(liste) { p in
                    Label(p.nom, systemImage: p.symbole(sens)).tag(p.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: Espace.s) {
                Image(systemName: courant?.symbole(sens) ?? "speaker.slash")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(courant?.nom ?? "Aucun")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let courant {
                        Text(courant.nature)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Espace.xs)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(liste.isEmpty)
        .accessibilityLabel(sens == .sortie ? "Choisir la sortie" : "Choisir l'entrée")
        .accessibilityValue(courant?.nom ?? "Aucun")
    }

    private func menuDebit(_ r: ReglagesPeripherique, sens: Sens) -> some View {
        HStack {
            Text("Fréquence")
            Spacer()
            Menu {
                Picker("Fréquence", selection: Binding(get: { r.debit },
                                                       set: { melangeur.reglerDebit($0, sens) })) {
                    ForEach(r.debits, id: \.self) { Text(khz($0)).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(khz(r.debit)).monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .help("Fréquence d'échantillonnage du périphérique")
    }

    /// Le curseur commun : bouton de coupure, curseur, pourcentage.
    private func curseur(valeur: Float, plage: ClosedRange<Float>, muet: Bool, libelle: String,
                         symboles: (String, String)? = nil,
                         course: Course = .lineaire,
                         regler: @escaping (Float, Bool) -> Void,
                         couper: (() -> Void)?) -> some View {
        HStack(spacing: Espace.s) {
            let symbole = symboles.map { muet ? $0.0 : $0.1 } ?? symboleVolume(valeur, muet: muet)
            if let couper {
                Button(action: couper) {
                    Image(systemName: symbole)
                        .frame(width: 18)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(muet ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .help(muet ? "Rétablir le son" : "Couper le son")
                .accessibilityLabel(muet ? "Rétablir le son" : "Couper le son")
            } else {
                Image(systemName: symbole)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            // La valeur passe tout de suite au son pendant le glissement ;
            // le relâchement enregistre.
            Slider(value: Binding(get: { course.position(valeur, plage) },
                                  set: { regler(course.valeur($0, plage), false) }),
                   in: 0...1,
                   onEditingChanged: { enCours in if !enCours { regler(valeur, true) } })
                .controlSize(.small)
                .accessibilityLabel(libelle)
                .accessibilityValue(muet ? "coupé" : pourcent(valeur))

            Text(muet ? "—" : pourcent(valeur))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(valeur > 1 && !muet ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func symboleVolume(_ v: Float?, muet: Bool) -> String {
        guard let v, !muet else { return muet ? "speaker.slash.fill" : "speaker.fill" }
        switch v {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default:      return "speaker.wave.3.fill"
        }
    }

    private func pourcent(_ v: Float) -> String {
        "\(Int((v * 100).rounded()))\u{00A0}%"
    }

    private func khz(_ debit: Double) -> String {
        (debit / 1000).formatted(.number.precision(.fractionLength(0...1))) + "\u{00A0}kHz"
    }
}

/// Comment la position du curseur se traduit en valeur.
///
/// `console` : l'unité (100 %) se trouve aux trois quarts de la course, comme
/// le repère « 0 dB » d'une tirette de table de mixage. Les trois premiers
/// quarts baissent, le dernier amplifie. C'est là qu'on règle presque
/// toujours, et c'est là qu'il faut de la précision — une course linéaire
/// de 0 à 200 % mettrait 100 % au milieu, qu'on lirait comme « à moitié ».
private enum Course {
    case lineaire, console

    static let unite: Double = 0.75

    func position(_ v: Float, _ plage: ClosedRange<Float>) -> Double {
        let lo = Double(plage.lowerBound), hi = Double(plage.upperBound), x = Double(v)
        switch self {
        case .lineaire:
            return (x - lo) / (hi - lo)
        case .console:
            if x <= 1 { return x * Self.unite }
            let auDela: Double = (x - 1) / (hi - 1)
            return Self.unite + auDela * (1 - Self.unite)
        }
    }

    func valeur(_ p: Double, _ plage: ClosedRange<Float>) -> Float {
        let lo = Double(plage.lowerBound), hi = Double(plage.upperBound)
        switch self {
        case .lineaire:
            return Float(lo + p * (hi - lo))
        case .console:
            if p <= Self.unite { return Float(p / Self.unite) }
            let auDela: Double = (p - Self.unite) / (1 - Self.unite)
            return Float(1 + auDela * (hi - 1))
        }
    }
}

private extension String {
    var capitalisee: String { prefix(1).uppercased() + dropFirst() }
}

/// L'icône d'une application, lue une fois puis gardée — comme dans Pouls.
private struct Icone: View {
    let bundlePath: String?
    let repli: String

    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        Group {
            if let image = Self.icone(bundlePath) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: repli)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tertiary)
                    .padding(2)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    @MainActor
    private static func icone(_ path: String?) -> NSImage? {
        guard let path else { return nil }
        if let connue = cache[path] { return connue }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}
