import Commun
import SwiftUI
import SMCKit

struct PanelView: View {
    @Bindable var monitor: Monitor
    @Bindable var commander: FanCommander
    @Environment(\.accessibilityReduceMotion) private var reduireMouvement

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            header
            temperatures
            fansSection
            controlSection
            footer
        }
        .padding(Espace.panneau)
        // Le passage Automatique / Manuel change la hauteur du panneau : on
        // l'adoucit, sauf si la personne a demandé moins de mouvement.
        .animation(reduireMouvement ? nil : .snappy(duration: 0.25), value: commander.isManual)
    }

    // MARK: Verdict

    private var header: some View {
        EnTete(symbole: verdictIcon,
               teinte: verdictColor,
               titre: monitor.verdict?.label ?? "—",
               detail: monitor.verdict?.explanation ?? "Lecture en cours…") {
            if let hotspot = monitor.thermal?.hotspot {
                // Le point chaud est la seule valeur « héros » : un cran au-dessus
                // du corps, en chiffres tabulaires pour ne pas trembler.
                Text(format(hotspot))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityLabel("Point chaud \(format(hotspot))")
            }
        }
    }

    private var verdictColor: Color {
        switch monitor.verdict?.severity ?? 1 {
        case 0: return .blue
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        default: return .red
        }
    }

    private var verdictIcon: String {
        switch monitor.verdict?.severity ?? 1 {
        case 0, 1: return "checkmark.circle.fill"
        case 2:    return "thermometer.medium"
        case 3:    return "thermometer.high"
        default:   return "exclamationmark.triangle.fill"
        }
    }

    // MARK: Températures

    private var temperatures: some View {
        Groupe("Températures") {
            row("Cœurs performance", monitor.thermal?.performanceCores)
            row("Cœurs efficience", monitor.thermal?.efficiencyCores)
            row("GPU", monitor.thermal?.gpu)
            row("Châssis", monitor.thermal?.chassis, hint: "ce que tu sens sur les jambes")
            row("Batterie", monitor.thermal?.battery)
        }
    }

    private func row(_ label: String, _ value: Double?, hint: String? = nil) -> some View {
        Ligne(label, value.map(format) ?? "—", aide: hint)
    }

    private func format(_ celsius: Double) -> String {
        String(format: "%.0f °C", celsius)
    }

    // MARK: Ventilateurs

    private var fansSection: some View {
        Groupe("Ventilateurs") {
            if monitor.fans.isEmpty {
                Text("Aucun ventilateur détecté")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(monitor.fans) { fan in
                VStack(alignment: .leading, spacing: Espace.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Espace.s) {
                        Text("Ventilateur \(fan.index + 1)")
                        if fan.mode.isManual {
                            Text("Manuel")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                        Spacer(minLength: Espace.s)
                        Text("\(Int(fan.actual)) RPM")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: fan.load)
                        .progressViewStyle(.linear)
                        .accessibilityHidden(true)
                    // Les bornes situent la jauge : de l'arrêt au plein régime.
                    HStack {
                        Text("\(Int(fan.minimum))")
                        Spacer()
                        Text("\(Int(fan.maximum))")
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue("\(Int(fan.actual)) RPM, charge \(Int(fan.load * 100)) %")
            }
        }
    }

    // MARK: Contrôle

    @ViewBuilder
    private var controlSection: some View {
        if commander.available {
            Groupe("Contrôle") {
                Picker("Mode", selection: modeBinding) {
                    Text("Automatique").tag(false)
                    Text("Manuel").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if commander.isManual {
                    HStack {
                        Text("Consigne")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(commander.sliderRPM)) RPM")
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                    }

                    // La consigne n'est envoyée qu'au relâchement : inutile de
                    // marteler le SMC à chaque pixel de glissement.
                    Slider(
                        value: $commander.sliderRPM,
                        in: commander.minimumRPM...commander.maximumRPM,
                        step: 50,
                        onEditingChanged: { editing in
                            guard !editing else { return }
                            Task { await commander.setManual(commander.sliderRPM) }
                        }
                    )
                    .accessibilityLabel("Consigne du ventilateur")

                    // Quatre boutons de même largeur : un réglage, pas une action
                    // principale, donc le style bordé discret du système.
                    HStack(spacing: Espace.xs) {
                        presetButton("Silencieux", ratio: 0.0)
                        presetButton("Équilibré", ratio: 0.35)
                        presetButton("Frais", ratio: 0.65)
                        presetButton("Max", ratio: 1.0)
                    }

                    if commander.safetyOverride {
                        Label("Consigne relevée : température critique",
                              systemImage: "exclamationmark.shield.fill")
                            .font(.caption)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            // Pas de démon : on explique et on dit quoi faire, sans bouton mort.
            Groupe {
                VStack(spacing: Espace.xs) {
                    Image(systemName: "lock.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("Contrôle manuel indisponible")
                        .font(.headline)
                    Text(commander.status ?? "Démon non installé.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("./install.sh")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, Espace.s).padding(.vertical, 2)
                        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 5))
                    Text("à lancer dans le dossier du projet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var modeBinding: Binding<Bool> {
        Binding(
            get: { commander.isManual },
            set: { wantsManual in
                Task {
                    if wantsManual {
                        await commander.setManual(commander.sliderRPM)
                    } else {
                        await commander.setAutomatic()
                    }
                }
            }
        )
    }

    private func presetButton(_ title: String, ratio: Double) -> some View {
        Button {
            let span = commander.maximumRPM - commander.minimumRPM
            let value = commander.minimumRPM + span * ratio
            commander.sliderRPM = value
            Task { await commander.setManual(value) }
        } label: {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Régler le ventilateur sur « \(title) »")
    }

    // MARK: Pied

    private var footer: some View {
        PiedDePanneau {
            if let error = monitor.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}
