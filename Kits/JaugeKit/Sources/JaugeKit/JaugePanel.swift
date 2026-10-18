import Commun
import SwiftUI

/// Le panneau de Jauge : deux anneaux, puis ce qu'ils veulent dire.
///
/// Tout est contenu, rien n'est en verre : le popover est déjà la couche qui
/// flotte. La seule couleur vive est celle qui alerte — orange à 80 %, rouge
/// à 90 %.
struct JaugePanel: View {
    @Bindable var jauge: Jauge

    var body: some View {
        // Les comptes à rebours vieillissent même sans nouveau relevé.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: Espace.l) {
                header(jauge.usage, now: context.date)
                if let usage = jauge.usage, usage.session != nil || usage.week != nil {
                    rings(usage, now: context.date)
                    Groupe("Session de 5 h") { sessionDetail(usage, now: context.date) }
                    Groupe("Semaine") { weekDetail(usage, now: context.date) }
                } else {
                    EtatVide(symbole: "gauge.with.dots.needle.0percent",
                             titre: "Aucun relevé pour l'instant",
                             detail: "Les chiffres arrivent à la prochaine réponse de Claude Code.")
                }
                if jauge.hookup != .connected {
                    Groupe("Branchement") { hookup }
                }
                Groupe("Alertes et relevés") { alerts(jauge.usage, now: context.date) }
                PiedDePanneau()
            }
            .padding(Espace.panneau)
        }
    }

    // MARK: Anneaux

    private func rings(_ usage: Usage, now: Date) -> some View {
        HStack(spacing: 0) {
            Ring(value: usage.session?.current(at: now), label: "Session")
                .frame(maxWidth: .infinity)
            Ring(value: usage.week?.current(at: now), label: "Semaine")
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }

    // MARK: Détails

    @ViewBuilder
    private func sessionDetail(_ usage: Usage, now: Date) -> some View {
        if let session = usage.session {
            if session.isExpired(at: now) {
                line("arrow.counterclockwise", "Remise à zéro : en attente de la prochaine réponse de Claude.")
            } else {
                line("clock", "Remise à zéro \(Jauge.remaining(until: session.resetsAt, from: now)), \(Jauge.moment(session.resetsAt)).")
                if let full = usage.sessionFull(at: now) {
                    line("exclamationmark.triangle", "À ce rythme, pleine vers \(full.formatted(date: .omitted, time: .shortened)).",
                         tint: .orange)
                } else if usage.knowsPace(at: now) {
                    line("checkmark.circle", "Au rythme actuel, elle tient jusqu'à la remise à zéro.")
                }
            }
        } else {
            line("questionmark.circle", "Pas encore de relevé de session.")
        }
    }

    @ViewBuilder
    private func weekDetail(_ usage: Usage, now: Date) -> some View {
        if let week = usage.week {
            if week.isExpired(at: now) {
                line("arrow.counterclockwise", "Nouvelle semaine : en attente de la prochaine réponse de Claude.")
            } else {
                line("calendar", "Remise à zéro \(Jauge.remaining(until: week.resetsAt, from: now)), \(Jauge.moment(week.resetsAt)).")
            }
        } else {
            line("questionmark.circle", "Pas encore de relevé hebdomadaire.")
        }
    }

    // MARK: En-tête

    /// Le verdict d'abord : est-ce que ça tient ?
    private func header(_ usage: Usage?, now: Date) -> some View {
        let session = usage?.session?.current(at: now) ?? 0
        let week = usage?.week?.current(at: now) ?? 0
        let worst = max(session, week)
        let titre: String = switch worst {
        case 100...: "Limite atteinte"
        case 90...: "Presque plein"
        case 80...: "À surveiller"
        default: usage == nil ? "Consommation Claude" : "Tout va bien"
        }
        let full = usage?.sessionFull(at: now)
        let detail = full.map { "À ce rythme, la session sera pleine vers \($0.formatted(date: .omitted, time: .shortened))." }
            ?? "Ta consommation Claude, session de 5 h et semaine."
        return EnTete(symbole: "gauge.with.dots.needle.50percent",
                      teinte: worst >= 90 ? .red : worst >= 80 ? .orange : .accentColor,
                      titre: titre, detail: detail)
    }

    // MARK: Branchement

    @ViewBuilder
    private var hookup: some View {
        switch jauge.hookup {
        case .connected:
            EmptyView()
        case .absent:
            Text("Claude Code doit transmettre ses chiffres à Jauge, par sa ligne d'état. Cela ajoute une ligne à ~/.claude/settings.json ; une copie de l'ancien fichier est gardée.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if Jauge.executable != nil {
                Button("Brancher Claude Code") { jauge.connect() }
                    .controlSize(.small)
            } else {
                Text("Installe d'abord l'app Jauge : c'est elle que Claude Code appelle.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .occupied(let command):
            Text("Une autre ligne d'état est déjà réglée dans Claude Code. Jauge n'y touche pas :")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(command)
                .font(.caption.monospaced())
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    // MARK: Alertes

    private func alerts(_ usage: Usage?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Prévenir à 80, 90 et 100 %", isOn: $jauge.alerts)
                .toggleStyle(.checkbox)
                .font(.callout)
            Toggle("Relevé automatique", isOn: $jauge.autoRefresh)
                .toggleStyle(.checkbox)
                .font(.callout)
            Text("Quand Claude sert hors du terminal (extension, app Claude), Jauge demande l'état toutes les 10 min par un appel Haiku minuscule : environ 0,0002 $.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let usage {
                HStack(spacing: 6) {
                    if jauge.refreshing { ProgressView().controlSize(.mini) }
                    Text(jauge.refreshing ? "Relevé en cours…" : "Dernier relevé \(Self.age(usage.updated, now: now)).")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// « à l'instant », « il y a 12 min ».
    private static func age(_ date: Date, now: Date) -> String {
        let age = Format.age(now.timeIntervalSince(date))
        return age == "à l'instant" ? age : "il y a \(age)"
    }

    private func line(_ symbol: String, _ text: String, tint: Color = .secondary) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.callout)
    }
}

/// Un anneau de consommation : le pourcentage au centre, le nom dessous.
struct Ring: View {
    let value: Double?
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max((value ?? 0) / 100, 0), 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.5), value: value)
                Text(value.map { "\(Int($0.rounded())) %" } ?? "—")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            .frame(width: 84, height: 84)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) : \(value.map { "\(Int($0.rounded())) pour cent" } ?? "inconnu")")
    }

    private var tint: Color {
        switch value ?? 0 {
        case ..<80: .accentColor
        case ..<90: .orange
        default: .red
        }
    }
}
