import AppKit
import Commun
import SwiftUI

struct PoulsPanel: View {
    @Bindable var pouls: Pouls
    @State private var critere: Critere = .cpu
    @Environment(\.accessibilityReduceMotion) private var reduireMouvement

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            header
            // Le panneau dépasse la hauteur d'un popover confortable dès qu'on
            // montre les cinq ressources : on le fait défiler plutôt que de
            // choisir à la place du lecteur ce qu'il n'a pas le droit de voir.
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    processeur
                    memoire
                    consommateurs
                    stockageEtReseau
                    conseils
                }
                .padding(.bottom, 2)
            }
            // Hauteur *fixe*, pas un plafond. Avec un simple `maxHeight`, la
            // mise en page du popover ne tirait de ce panneau aucune hauteur
            // utilisable : il s'ouvrait à la taille par défaut d'un NSPopover,
            // 320 pt, et s'arrêtait au milieu de la mémoire. Mesuré : la même
            // vue rend 557 pt de `fittingSize` une fois la hauteur posée ici.
            // 440 pt montrent à peu près la moitié du contenu, le reste défile.
            .frame(height: 440)
            footer
        }
        .padding(Espace.panneau)
    }

    private var teinte: Color {
        switch pouls.etat.severity {
        case 0: .blue
        case 1: .green
        case 2: .orange
        default: .red
        }
    }

    // MARK: En-tête

    private var header: some View {
        EnTete(symbole: pouls.etat.symbol,
               teinte: teinte,
               titre: pouls.etat.label,
               detail: pouls.etat.explanation) {
            // La charge est la valeur « héros » : un cran au-dessus du corps,
            // en chiffres tabulaires pour ne pas trembler à chaque relevé.
            Text(Chiffre.part(pouls.cpu.total))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .accessibilityLabel("Charge processeur \(Chiffre.part(pouls.cpu.total))")
        }
    }

    // MARK: Processeur

    private var processeur: some View {
        Groupe("Processeur") {
            Courbe(values: pouls.history, teinte: teinte)
                .frame(height: 36)
                .accessibilityHidden(true)

            HStack(spacing: Espace.s) {
                legende("Apps", Chiffre.part(pouls.cpu.user), teinte)
                legende("Système", Chiffre.part(pouls.cpu.system), .secondary)
                Spacer(minLength: 0)
                Text("\(pouls.cpu.cores) cœurs")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func legende(_ titre: String, _ valeur: String, _ couleur: some ShapeStyle) -> some View {
        HStack(spacing: Espace.xs) {
            Circle()
                .fill(couleur)
                .frame(width: 6, height: 6)
            Text(titre)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(valeur)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        // Trois légendes sur 300 pt : sans ça, « Applications » se coupe en
        // deux lignes et la rangée se met à respirer à chaque relevé.
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    // MARK: Mémoire

    @ViewBuilder
    private var memoire: some View {
        if let memory = pouls.memory {
            Groupe("Mémoire") {
                Barre(segments: [
                    .init(part: Double(memory.app) / Double(memory.total), couleur: teinte),
                    .init(part: Double(memory.wired) / Double(memory.total), couleur: .secondary),
                    .init(part: Double(memory.compressed) / Double(memory.total), couleur: .orange),
                ])
                .accessibilityHidden(true)

                Ligne("Utilisée",
                      "\(Chiffre.octets(memory.used)) sur \(Chiffre.octets(memory.total))")
                Ligne("Pression", memory.pression.label,
                      aide: memory.pression == .normale ? nil : "macOS comprime pour faire tenir")
                // Le cache n'est pas de la mémoire perdue : macOS le rend dès
                // qu'une application en a besoin. Le dire évite de compter
                // une machine pleine là où elle est simplement bien remplie.
                Ligne("Fichiers en cache", Chiffre.octets(memory.cached),
                      aide: "rendus à la demande")
                if memory.swapUsed > 0 {
                    Ligne("Sur le disque", Chiffre.octets(memory.swapUsed), aide: "swap")
                }
            }
        }
    }

    // MARK: Ce qui consomme

    private var consommateurs: some View {
        Groupe("Ce qui consomme") {
            Picker("Critère", selection: $critere) {
                ForEach(Critere.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if pouls.warmingUp {
                Text("Mesure en cours…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Espace.s)
            } else {
                VStack(spacing: 2) {
                    ForEach(classement) { app in
                        rangee(app)
                    }
                    if critere == .cpu, pouls.systemShare > 0.03 {
                        systeme
                    }
                }
                .animation(reduireMouvement ? nil : .snappy(duration: 0.2), value: critere)
            }
        }
    }

    private var classement: [AppUsage] {
        let tri = pouls.apps.sorted { valeur($0) > valeur($1) }
        // Sous le seuil d'affichage, une ligne ne dit rien : une application
        // à 0 % n'est pas « ce qui consomme ».
        return Array(tri.filter { valeur($0) > seuil }.prefix(5))
    }

    private func valeur(_ app: AppUsage) -> Double {
        switch critere {
        case .cpu:     app.cpu
        case .memoire: Double(app.memory)
        case .disque:  app.disk
        }
    }

    private var seuil: Double {
        switch critere {
        case .cpu:     0.002           // 0,2 % de la machine
        case .memoire: 64 * 1_048_576  // 64 Mo
        case .disque:  32 * 1_024      // 32 ko/s
        }
    }

    private func texte(_ app: AppUsage) -> String {
        switch critere {
        case .cpu:     Chiffre.part(app.cpu)
        case .memoire: Chiffre.octets(app.memory)
        case .disque:  Chiffre.debit(app.disk)
        }
    }

    /// La part de la ligne la plus gourmande — c'est elle qui fixe l'échelle
    /// des barres, sinon une machine au repos n'afficherait que des traits.
    private func part(_ app: AppUsage) -> Double {
        let tete = classement.map(valeur).max() ?? 0
        guard tete > 0 else { return 0 }
        return valeur(app) / tete
    }

    private func rangee(_ app: AppUsage) -> some View {
        HStack(spacing: Espace.s) {
            Icone(bundlePath: app.bundlePath)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if app.processes > 1 {
                    Text("\(app.processes) processus")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: Espace.xs)
            Text(texte(app))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Espace.s)
        .padding(.vertical, 4)
        // La barre passe derrière la ligne plutôt qu'en dessous : elle donne
        // l'ordre de grandeur sans ajouter une seconde rangée à lire.
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 6)
                    .fill(teinte.opacity(0.16))
                    .frame(width: max(2, geo.size.width * part(app)))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), \(texte(app))")
    }

    private var systeme: some View {
        HStack(spacing: Espace.s) {
            Image(systemName: "gearshape.2")
                .frame(width: 18, height: 18)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 0) {
                Text("Système").foregroundStyle(.secondary)
                Text("processus de root")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: Espace.xs)
            Text(Chiffre.part(pouls.systemShare))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Espace.s)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Disque et réseau

    @ViewBuilder
    private var stockageEtReseau: some View {
        Groupe("Disque et réseau") {
            if let disk = pouls.disk {
                Barre(segments: [.init(part: disk.ratio, couleur: disk.ratio > 0.9 ? .red : .secondary)])
                    .accessibilityHidden(true)
                Ligne(disk.name, "\(Chiffre.disque(disk.free)) libres",
                      aide: "sur \(Chiffre.disque(disk.total))")
            }
            HStack(spacing: Espace.m) {
                debit("arrow.down", pouls.network.down, "Réception")
                debit("arrow.up", pouls.network.up, "Envoi")
                Spacer(minLength: 0)
            }
        }
    }

    private func debit(_ symbole: String, _ valeur: Double, _ label: String) -> some View {
        HStack(spacing: Espace.xs) {
            Image(systemName: symbole)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Chiffre.debit(valeur))
                .monospacedDigit()
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(Chiffre.debit(valeur))")
    }

    // MARK: Conseils

    @ViewBuilder
    private var conseils: some View {
        if !pouls.conseils.isEmpty {
            Groupe("Conseils") {
                ForEach(pouls.conseils) { conseil in
                    Label {
                        Text(conseil.text)
                            .font(.subheadline)
                            .foregroundStyle(conseil.severity > 0 ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: conseil.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(couleur(conseil.severity))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func couleur(_ severity: Int) -> Color {
        switch severity {
        case 2: .red
        case 1: .orange
        default: .secondary
        }
    }

    // MARK: Pied

    private var footer: some View {
        PiedDePanneau {
            Toggle("Dans la barre", isOn: $pouls.badgeEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Afficher la charge processeur à côté de l'icône")
        }
    }
}

// MARK: - Pièces

/// Une barre segmentée : chaque part dans sa teinte, le reste en creux.
private struct Barre: View {
    struct Segment {
        let part: Double
        let couleur: Color
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.couleur)
                        .frame(width: max(0, geo.size.width * min(1, segment.part)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(.quaternary, in: .capsule)
        .clipShape(.capsule)
    }
}

/// La courbe des soixante dernières mesures.
///
/// Dessinée dans un `Canvas` : une pile de soixante rectangles SwiftUI
/// coûterait soixante vues recalculées à chaque relevé pour le même trait.
private struct Courbe: View {
    let values: [Double]
    let teinte: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(max(1, 59))
            // Les valeurs arrivent par la droite : la mesure la plus récente
            // est au bord, comme sur tous les moniteurs système.
            let offset = size.width - step * CGFloat(values.count - 1)

            var line = Path()
            for (index, value) in values.enumerated() {
                let x = offset + step * CGFloat(index)
                let y = size.height - size.height * CGFloat(min(1, max(0, value)))
                index == 0 ? line.move(to: CGPoint(x: x, y: y)) : line.addLine(to: CGPoint(x: x, y: y))
            }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: offset, y: size.height))
            area.closeSubpath()

            context.fill(area, with: .linearGradient(
                Gradient(colors: [teinte.opacity(0.35), teinte.opacity(0.03)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(teinte),
                           style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
    }
}

/// L'icône d'une application, lue une fois puis gardée.
///
/// `NSWorkspace.icon(forFile:)` touche le disque : la rappeler à chaque relevé
/// ferait travailler le stockage pour afficher qui travaille le stockage.
private struct Icone: View {
    let bundlePath: String?

    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        Group {
            if let image = Self.icone(bundlePath) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "terminal")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tertiary)
                    .padding(2)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    @MainActor
    private static func icone(_ path: String?) -> NSImage? {
        guard let path else { return nil }
        if let known = cache[path] { return known }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}
