import Commun
import SwiftUI

struct PanelView: View {
    @Bindable var store: FonteStore
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.l) {
            EnTete(symbole: "textformat",
                   titre: "Police à l'écran",
                   detail: store.status ?? "Sélectionne du texte, Claude te dit quelle police c'est.")
            obstacles
            action
            if let latest = store.latest {
                Groupe("Dernière analyse") { last(latest) }
            }
            Groupe("Réglages") { options }
            PiedDePanneau()
        }
        .padding(Espace.panneau)
        .onAppear { store.refreshPermission() }
    }

    // MARK: Ce qui bloque

    @ViewBuilder
    private var obstacles: some View {
        // Sur preuve seulement, comme dans Grab : un avertissement affiché à
        // tort devant une case cochée est pire qu'aucun avertissement.
        if store.captureDenied {
            VStack(alignment: .leading, spacing: 6) {
                Label("La capture est revenue vide", systemImage: "lock.fill")
                    .font(.callout.weight(.medium))
                Text("macOS n'a pas laissé \(FonteStore.host) lire l'écran.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Ouvrir les réglages") { store.requestPermission() }
                        .controlSize(.small)
                    Button("Réessayer") { store.clearDenial() }
                        .controlSize(.small)
                }
                Text("Cocher \(FonteStore.host) dans Enregistrement de l'écran, puis relancer \(FonteStore.host). Si c'est déjà coché, « Réessayer » suffit.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Espace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
        } else if !store.claudeAvailable {
            VStack(alignment: .leading, spacing: 4) {
                Label("Claude Code introuvable", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                Text("C'est lui qui reconnaît la police. Installe-le, ouvre `claude` une fois dans Terminal pour te connecter, puis reviens ici.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Espace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
        } else if !store.hotkeyWorks {
            Label("Raccourci déjà pris par une autre app — choisis-en un autre ci-dessous.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Capture

    private var action: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.capture() }
            } label: {
                Label("Capturer", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(store.capturing)

            if store.capturing || store.analyzingCount > 0 {
                ProgressView().controlSize(.small)
            } else {
                Text(store.shortcut.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Dernière analyse

    private func last(_ analysis: Analysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Thumbnail(image: store.image(analysis), width: 64, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(analysis.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(detail(analysis))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button("Tout l'historique (\(store.analyses.count))", action: open)
                .controlSize(.small)
        }
    }

    private func detail(_ analysis: Analysis) -> String {
        switch analysis.state {
        case .analyzing: store.steps[analysis.id] ?? "Claude examine les lettres…"
        case .failed: "À réessayer depuis la fenêtre"
        case .done(let verdict):
            if let best = verdict.best {
                "\(best.confidence) % · \(best.style)"
            } else {
                "Aucune police reconnue"
            }
        }
    }

    // MARK: Réglages

    private var options: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Icône dans la barre de menus", isOn: $store.showIcon)
                .toggleStyle(.checkbox)
                .font(.callout)

            if store.showIcon {
                Text("Décoche pour libérer une place : le raccourci continue de marcher, et relancer \(FonteStore.host) fait revenir l'icône.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Raccourci").font(.callout)
                Spacer()
                Picker("", selection: $store.shortcut) {
                    ForEach(Shortcut.all) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}
