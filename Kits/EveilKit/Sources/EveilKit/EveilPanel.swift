import Commun
import SwiftUI

struct PanelView: View {
    @Bindable var awake: Awake
    @State private var apps: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            durations
            Divider()
            options
            Divider()
            footer
        }
        .padding(14)
        .onAppear { refreshApps() }
    }

    // MARK: État

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(awake.isActive ? Color.orange : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(awake.isActive ? "Éveillée" : "Veille normale")
                    .font(.headline)
                Text(awake.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Durées

    private var durations: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                duration("30 min", minutes: 30)
                duration("1 h", minutes: 60)
                duration("2 h", minutes: 120)
                duration("4 h", minutes: 240)
            }

            HStack(spacing: 6) {
                Button {
                    awake.start(.indefinite)
                } label: {
                    Label("Sans limite", systemImage: "infinity")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isIndefinite ? .orange : nil)

                if awake.isActive {
                    Button("Arrêter") { awake.stop() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            // Une session déjà lancée se prolonge au lieu d'être relancée :
            // c'est le geste qu'on fait vraiment quand un build déborde.
            if awake.deadline != nil {
                Button("Prolonger de 30 min") { awake.extend(by: 30 * 60) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private var isIndefinite: Bool {
        if case .indefinite = awake.reason { return true }
        return false
    }

    private func duration(_ title: String, minutes: Int) -> some View {
        Button(title) {
            awake.start(.until(Date().addingTimeInterval(Double(minutes) * 60)))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    // MARK: Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Garder l'écran allumé", isOn: $awake.keepDisplayOn)
                .toggleStyle(.checkbox)
                .font(.callout)

            Text(awake.keepDisplayOn
                 ? "L'écran reste allumé. Utile pour une présentation, inutile pour un build."
                 : "Seule la mise en veille système est bloquée. L'écran s'éteint normalement.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Menu {
                if apps.isEmpty {
                    Text("Aucune app à surveiller")
                } else {
                    ForEach(apps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? "?") {
                            guard let bundleID = app.bundleIdentifier else { return }
                            awake.start(.app(bundleID: bundleID,
                                             name: app.localizedName ?? bundleID))
                        }
                    }
                }
            } label: {
                Label(awake.watchedApp.map { "Tant que \($0) tourne" }
                      ?? "Tant qu'une app tourne…", systemImage: "app.badge.checkmark")
            }
            .menuStyle(.borderlessButton)
            .font(.callout)
            .onTapGesture { refreshApps() }
        }
    }

    /// La liste des apps est relue à chaque ouverture : celle qu'on veut
    /// surveiller vient souvent d'être lancée.
    private func refreshApps() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    // MARK: Pied

    private var footer: some View {
        HStack {
            if let minutes = awake.minutesLeft {
                Text(minutes >= 60
                     ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
                     : "\(minutes) min")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quitter") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
}
