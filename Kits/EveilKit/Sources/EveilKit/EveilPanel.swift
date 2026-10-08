import Commun
import SwiftUI

struct PanelView: View {
    @Bindable var awake: Awake
    @State private var apps: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            header
            durations
            options
            PiedDePanneau()
        }
        .padding(Espace.panneau)
        .onAppear { refreshApps() }
    }

    // MARK: État

    private var header: some View {
        EnTete(symbole: awake.isActive ? "cup.and.saucer.fill" : "moon.zzz.fill",
               teinte: awake.isActive ? .orange : .secondary,
               titre: awake.isActive ? "Éveillée" : "Veille normale",
               detail: awake.summary) {
            // Le temps restant est la seule valeur qui change à la minute :
            // chiffres tabulaires, pour qu'elle ne saute pas.
            if let minutes = awake.minutesLeft {
                Text(minutes >= 60
                     ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
                     : "\(minutes) min")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Durées

    private var durations: some View {
        Groupe("Garder éveillée") {
            HStack(spacing: Espace.s) {
                duration("30 min", minutes: 30)
                duration("1 h", minutes: 60)
                duration("2 h", minutes: 120)
                duration("4 h", minutes: 240)
            }

            HStack(spacing: Espace.s) {
                // La session en cours (sans limite) est la seule qu'on sache
                // désigner : elle passe en prominent, c'est l'état, pas un décor.
                if isIndefinite {
                    indefiniteButton.buttonStyle(.borderedProminent)
                } else {
                    indefiniteButton.buttonStyle(.bordered)
                }

                if awake.isActive {
                    Button("Arrêter") { awake.stop() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .help("Revenir à la veille normale")
                }
            }

            // Une session déjà lancée se prolonge au lieu d'être relancée :
            // c'est le geste qu'on fait vraiment quand un build déborde.
            if awake.deadline != nil {
                Button("Prolonger de 30 min") { awake.extend(by: 30 * 60) }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
        }
    }

    private var indefiniteButton: some View {
        Button {
            awake.start(.indefinite)
        } label: {
            Label("Sans limite", systemImage: "infinity")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .tint(.orange)
        .help("Rester éveillée jusqu'à l'arrêt")
    }

    private var isIndefinite: Bool {
        if case .indefinite = awake.reason { return true }
        return false
    }

    private func duration(_ title: String, minutes: Int) -> some View {
        Button {
            awake.start(.until(Date().addingTimeInterval(Double(minutes) * 60)))
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: Options

    private var options: some View {
        Groupe("Options") {
            // Interrupteur plutôt que case : c'est un réglage qui prend effet
            // tout de suite, sans « valider », comme dans Centre de contrôle.
            HStack(alignment: .top, spacing: Espace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Garder l'écran allumé")
                    Text(awake.keepDisplayOn
                         ? "Utile pour une présentation, inutile pour un build."
                         : "Seule la veille système est bloquée.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Espace.s)
                Toggle("Garder l'écran allumé", isOn: $awake.keepDisplayOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider()

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
                    .symbolRenderingMode(.hierarchical)
            }
            .menuStyle(.button)
            .controlSize(.small)
            .help("Rester éveillée tant qu'une app choisie est ouverte")
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
}
