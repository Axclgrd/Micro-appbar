import Commun
import SwiftUI
import SMCKit

struct PanelView: View {
    @Bindable var monitor: Monitor
    @Bindable var commander: FanCommander

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            temperatures
            Divider()
            fansSection
            Divider()
            controlSection
            Divider()
            footer
        }
        .padding(14)
    }

    // MARK: Verdict

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: verdictIcon)
                .font(.title2)
                .foregroundStyle(verdictColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(monitor.verdict?.label ?? "—")
                        .font(.headline)
                    if let hotspot = monitor.thermal?.hotspot {
                        Text(format(hotspot))
                            .font(.headline)
                            .foregroundStyle(verdictColor)
                    }
                }
                Text(monitor.verdict?.explanation ?? "Lecture en cours…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        VStack(spacing: 5) {
            row("Cœurs performance", monitor.thermal?.performanceCores)
            row("Cœurs efficience", monitor.thermal?.efficiencyCores)
            row("GPU", monitor.thermal?.gpu)
            row("Châssis", monitor.thermal?.chassis, hint: "ce que tu sens sur les jambes")
            row("Batterie", monitor.thermal?.battery)
        }
    }

    private func row(_ label: String, _ value: Double?, hint: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.callout)
                if let hint {
                    Text(hint).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(value.map(format) ?? "—")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ celsius: Double) -> String {
        String(format: "%.0f °C", celsius)
    }

    // MARK: Ventilateurs

    private var fansSection: some View {
        VStack(spacing: 8) {
            ForEach(monitor.fans) { fan in
                VStack(spacing: 3) {
                    HStack {
                        Text("Ventilateur \(fan.index + 1)").font(.callout)
                        if fan.mode.isManual {
                            Text("manuel")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                        }
                        Spacer()
                        Text("\(Int(fan.actual)) RPM")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: fan.load)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("\(Int(fan.minimum))").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(Int(fan.maximum))").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            if monitor.fans.isEmpty {
                Text("Aucun ventilateur détecté")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Contrôle

    @ViewBuilder
    private var controlSection: some View {
        if commander.available {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: modeBinding) {
                    Text("Automatique").tag(false)
                    Text("Manuel").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if commander.isManual {
                    HStack {
                        Text("Consigne").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(commander.sliderRPM)) RPM")
                            .font(.callout.monospacedDigit().weight(.medium))
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

                    HStack(spacing: 6) {
                        presetButton("Silencieux", ratio: 0.0)
                        presetButton("Équilibré", ratio: 0.35)
                        presetButton("Frais", ratio: 0.65)
                        presetButton("Max", ratio: 1.0)
                    }

                    if commander.safetyOverride {
                        Label("Consigne relevée : température critique",
                              systemImage: "exclamationmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Label("Contrôle manuel indisponible", systemImage: "lock.fill")
                    .font(.callout.weight(.medium))
                Text(commander.status ?? "Démon non installé.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Lancer ./install.sh dans le dossier du projet.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
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
        Button(title) {
            let span = commander.maximumRPM - commander.minimumRPM
            let value = commander.minimumRPM + span * ratio
            commander.sliderRPM = value
            Task { await commander.setManual(value) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption2)
    }

    // MARK: Pied

    private var footer: some View {
        HStack {
            if let error = monitor.error {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
            Spacer()
            Button("Quitter") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
}
