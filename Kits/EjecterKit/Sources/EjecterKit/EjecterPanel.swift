import Commun
import SwiftUI

struct PanelView: View {
    @Bindable var store: DiskStore

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            EnTete(symbole: "externaldrive.connected.to.line.below",
                   titre: "Disques externes",
                   detail: summary)

            if store.devices.isEmpty {
                EtatVide(symbole: "externaldrive.badge.checkmark",
                         titre: "Rien à éjecter",
                         detail: "Aucun disque externe ni image disque montée.")
            } else {
                ForEach(store.devices) { device in
                    card(device)
                }
            }

            footer
        }
        .padding(Espace.panneau)
        .onAppear { store.panelVisible = true }
        .onDisappear { store.panelVisible = false }
    }

    // MARK: En-tête

    private var summary: String {
        let mounted = store.devices.filter(\.isMounted).count
        let dormant = store.devices.filter(\.isDormant).count
        switch (mounted, dormant) {
        case (0, 0):  return "Rien de branché."
        case (_, 0):  return "\(mounted) monté\(mounted > 1 ? "s" : "")."
        case (0, _):  return "\(dormant) branché\(dormant > 1 ? "s" : ""), non monté."
        default:      return "\(mounted) monté\(mounted > 1 ? "s" : ""), \(dormant) en veille."
        }
    }

    // MARK: Un disque

    // Une surface par disque (et non des filets entre eux) : l'éjection agit
    // sur un disque entier, la surface dit où commence et finit son périmètre.
    @ViewBuilder
    private func card(_ device: Device) -> some View {
        Groupe {
            HStack(alignment: .center, spacing: Espace.m) {
                Image(systemName: device.kind == .image ? "opticaldiscdrive.fill" : "externaldrive.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(device.isMounted ? Color.accentColor : .secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(subtitle(device))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Espace.xs)
                actions(device)
            }

            if device.isMounted, let free = device.free {
                VStack(spacing: Espace.xs) {
                    ProgressView(value: device.fill)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Espace utilisé")
                        .accessibilityValue(device.fill.formatted(.percent.precision(.fractionLength(0))))
                    HStack {
                        Text("\(bytes(free)) libres")
                        Spacer()
                        Text(bytes(device.capacity))
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }

            if device.isDormant {
                Label("Branché mais non monté : rien ne le lit.", systemImage: "moon.zzz.fill")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }

            // Plusieurs volumes sur le même disque : on les nomme, sinon
            // « éjecter » a l'air de ne concerner qu'un seul d'entre eux.
            if device.volumes.count > 1 {
                Text(device.volumes.map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            outcome(device)
        }
    }

    private func subtitle(_ device: Device) -> String {
        device.kind == .image ? "Image disque" : device.model
    }

    @ViewBuilder
    private func actions(_ device: Device) -> some View {
        if store.busy.contains(device.id) {
            // Un indicateur seul ne dit pas quoi ; le libellé évite de croire
            // à un blocage pendant que diskutil travaille.
            HStack(spacing: Espace.s) {
                ProgressView().controlSize(.small)
                Text("En cours…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if device.isMounted {
            HStack(spacing: Espace.xs) {
                Button("Éjecter") { Task { await store.eject(device) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Éjecter \(device.name)")

                Menu {
                    // Réservé aux disques matériels : une image démontée mais
                    // toujours attachée n'apparaît plus nulle part, on ne veut
                    // pas offrir un geste qui la ferait disparaître sans retour.
                    if device.kind == .drive {
                        Button("Démonter (garder branché)") { Task { await store.unmount(device) } }
                    }
                    if let mount = device.mountedVolumes.first?.mountPoint {
                        Button("Ouvrir dans le Finder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: mount))
                        }
                    }
                    Divider()
                    Button("Forcer l'éjection", role: .destructive) {
                        Task { await store.forceEject(device) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Autres actions")
                .accessibilityLabel("Autres actions pour \(device.name)")
            }
        } else {
            Button("Remonter") { Task { await store.mount(device) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Remonter \(device.name)")
        }
    }

    // MARK: Après une action

    @ViewBuilder
    private func outcome(_ device: Device) -> some View {
        if let report = store.report[device.id] {
            VStack(alignment: .leading, spacing: Espace.s) {
                Divider()

                HStack(alignment: .firstTextBaseline, spacing: Espace.s) {
                    Image(systemName: report.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(report.ok ? .green : .orange)
                        .accessibilityHidden(true)
                    Text(report.ok ? report.message : "Éjection refusée.")
                        .font(.subheadline.weight(report.ok ? .regular : .medium))
                        .foregroundStyle(report.ok ? .secondary : .primary)
                    Spacer(minLength: Espace.xs)
                    Button {
                        store.dismiss(device)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Fermer ce message")
                    .accessibilityLabel("Fermer le message")
                }
                .fixedSize(horizontal: false, vertical: true)

                if !report.ok {
                    // Le message brut de diskutil est en anglais et technique,
                    // mais c'est la seule source de vérité quand l'échec n'a
                    // rien à voir avec un processus fautif (disque en panne,
                    // volume protégé). On le garde, en second plan.
                    Text(report.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    blockers(device)
                }
            }
        }
    }

    @ViewBuilder
    private func blockers(_ device: Device) -> some View {
        let list = store.blockers[device.id] ?? []

        VStack(alignment: .leading, spacing: Espace.s) {
            if list.isEmpty {
                Text("Aucun processus visible. C'est en général Spotlight ou Time Machine, qui tournent sous root et échappent au relevé : attends quelques secondes, ou force.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Utilisé par")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(list) { blocker in
                    HStack(spacing: Espace.s) {
                        if let icon = appIcon(blocker) {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "terminal")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(appName(blocker))
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            if let sample = blocker.sample {
                                Text(sample)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Spacer(minLength: Espace.xs)
                        Button("Quitter") { Task { await store.quit(blocker, for: device) } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Quitter \(appName(blocker))")
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, Espace.xs)
                    .survol()
                }
            }

            // « Réessayer » est le geste sûr ; « Forcer » risque de perdre
            // des données non écrites, il reste donc secondaire et rouge.
            HStack(spacing: Espace.s) {
                Button("Réessayer") { Task { await store.eject(device) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Forcer", role: .destructive) { Task { await store.forceEject(device) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Éjecter malgré les processus : des données non écrites peuvent être perdues")
                Spacer()
            }
        }
    }

    /// Le nom du processus vu par `lsof` est un nom d'exécutable ; celui que
    /// l'utilisateur connaît est celui de l'app. On préfère le second.
    private func appName(_ blocker: Blocker) -> String {
        NSRunningApplication(processIdentifier: blocker.pid)?.localizedName ?? blocker.command
    }

    private func appIcon(_ blocker: Blocker) -> NSImage? {
        NSRunningApplication(processIdentifier: blocker.pid)?.icon
    }

    // MARK: Pied

    private var footer: some View {
        PiedDePanneau {
            Toggle("Toujours afficher", isOn: $store.alwaysVisible)
                .toggleStyle(.checkbox)
                .help("Garder l'icône dans la barre des menus même sans disque")

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Actualiser la liste")
            .accessibilityLabel("Actualiser")
        }
    }

    private func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }
}
