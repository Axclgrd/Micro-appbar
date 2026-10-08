import Commun
import SwiftUI

struct PanelView: View {
    @Bindable var store: DiskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            if store.devices.isEmpty {
                empty
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(store.devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { Divider() }
                        card(device)
                    }
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .onAppear { store.panelVisible = true }
        .onDisappear { store.panelVisible = false }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Disques externes").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

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

    private var empty: some View {
        Text("Aucun disque externe ni image disque montée.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Un disque

    @ViewBuilder
    private func card(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: device.kind == .image ? "opticaldiscdrive.fill" : "externaldrive.fill")
                    .foregroundStyle(device.isMounted ? Color.accentColor : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(subtitle(device))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
                actions(device)
            }

            if device.isMounted, let free = device.free {
                VStack(spacing: 3) {
                    ProgressView(value: device.fill)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("\(bytes(free)) libres").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(bytes(device.capacity)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            if device.isDormant {
                Label("Branché mais non monté — rien ne le lit.", systemImage: "moon.zzz.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Plusieurs volumes sur le même disque : on les nomme, sinon
            // « éjecter » a l'air de ne concerner qu'un seul d'entre eux.
            if device.volumes.count > 1 {
                Text(device.volumes.map(\.name).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
            ProgressView().controlSize(.small)
        } else if device.isMounted {
            HStack(spacing: 2) {
                Button("Éjecter") { Task { await store.eject(device) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

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
                    Button("Forcer l'éjection") { Task { await store.forceEject(device) } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        } else {
            Button("Remonter") { Task { await store.mount(device) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: Après une action

    @ViewBuilder
    private func outcome(_ device: Device) -> some View {
        if let report = store.report[device.id] {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: report.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(report.ok ? .green : .orange)
                    Text(report.ok ? report.message : "Éjection refusée.")
                        .foregroundStyle(report.ok ? .secondary : .primary)
                    Spacer()
                    Button {
                        store.dismiss(device)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

                if !report.ok {
                    // Le message brut de diskutil est en anglais et technique,
                    // mais c'est la seule source de vérité quand l'échec n'a
                    // rien à voir avec un processus fautif (disque en panne,
                    // volume protégé). On le garde, en second plan.
                    Text(report.message)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    blockers(device)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func blockers(_ device: Device) -> some View {
        let list = store.blockers[device.id] ?? []

        VStack(alignment: .leading, spacing: 6) {
            if list.isEmpty {
                Text("Aucun processus visible. C'est en général Spotlight ou Time Machine, qui tournent sous root et échappent au relevé — attends quelques secondes, ou force.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(list) { blocker in
                    HStack(spacing: 6) {
                        if let icon = appIcon(blocker) {
                            Image(nsImage: icon).resizable().frame(width: 15, height: 15)
                        } else {
                            Image(systemName: "terminal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 15)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(appName(blocker))
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            if let sample = blocker.sample {
                                Text(sample)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Spacer(minLength: 2)
                        Button("Quitter") { Task { await store.quit(blocker, for: device) } }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                    }
                }
            }

            HStack(spacing: 6) {
                Button("Réessayer") { Task { await store.eject(device) } }
                    .controlSize(.small)
                Button("Forcer") { Task { await store.forceEject(device) } }
                    .controlSize(.small)
                    .tint(.orange)
                Spacer()
            }
            .font(.caption2)
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
        HStack {
            Toggle("Toujours afficher", isOn: $store.alwaysVisible)
                .toggleStyle(.checkbox)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quitter") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }
}
