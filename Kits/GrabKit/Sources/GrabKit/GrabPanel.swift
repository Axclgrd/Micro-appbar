import Commun
import SwiftUI

struct PanelView: View {
    @Bindable var grabber: Grabber

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            obstacles
            action
            if grabber.text != nil {
                Divider()
                result
            }
            Divider()
            options
            Divider()
            footer
        }
        .padding(14)
        .onAppear { grabber.refreshPermission() }
    }

    // MARK: Ce qui bloque

    @ViewBuilder
    private var obstacles: some View {
        // Sur preuve seulement — c'est-à-dire après une capture réellement
        // revenue vide. Tant qu'on n'a rien essayé, on ne prétend rien : un
        // avertissement affiché à tort devant une case cochée est pire
        // qu'aucun avertissement.
        if grabber.captureDenied {
            VStack(alignment: .leading, spacing: 6) {
                Label("La capture est revenue vide", systemImage: "lock.fill")
                    .font(.callout.weight(.medium))
                Text("macOS n'a pas laissé \(Grabber.host) lire l'écran.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Ouvrir les réglages") { grabber.requestPermission() }
                        .controlSize(.small)
                    Button("Réessayer") { grabber.clearDenial() }
                        .controlSize(.small)
                }
                // C'est l'app *hôte* qu'il faut cocher, pas l'outil : chercher « Grab »
                // dans la liste alors que c'est Trousse qui capture, c'est chercher une
                // ligne qui n'existe pas.
                Text("Cocher \(Grabber.host) dans Enregistrement de l'écran, puis relancer \(Grabber.host). Si c'est déjà coché, « Réessayer » suffit.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        } else if !grabber.hotkeyWorks {
            Label("Raccourci déjà pris par une autre app — choisis-en un autre ci-dessous.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.viewfinder")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Texte à l'écran").font(.headline)
                Text(grabber.status ?? "Sélectionne une zone, le texte part dans le presse-papier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Capture

    private var action: some View {
        HStack(spacing: 8) {
            Button {
                Task { await grabber.capture() }
            } label: {
                Label("Capturer", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(grabber.working)

            if grabber.working {
                ProgressView().controlSize(.small)
            } else {
                Text(grabber.shortcut.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Résultat

    private var result: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                Text(grabber.text ?? "")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 150)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button("Recopier") { grabber.copy() }
                    .controlSize(.small)
                Button("Effacer") { grabber.forget() }
                    .controlSize(.small)
                Spacer()
            }
            .font(.caption2)
        }
    }

    // MARK: Réglages

    private var options: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Correction linguistique", isOn: $grabber.languageCorrection)
                .toggleStyle(.checkbox)
                .font(.callout)

            Text(grabber.languageCorrection
                 ? "Vision corrige les mots abîmés — et réécrit parfois un identifiant ou une commande."
                 : "Texte rendu tel quel. C'est ce qu'il faut pour du code et des messages d'erreur.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Icône dans la barre de menus", isOn: $grabber.showIcon)
                .toggleStyle(.checkbox)
                .font(.callout)

            if grabber.showIcon {
                Text("Décoche pour libérer une place : le raccourci continue de marcher, et relancer \(Grabber.host) fait revenir l'icône.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Raccourci").font(.callout)
                Spacer()
                Picker("", selection: $grabber.shortcut) {
                    ForEach(Shortcut.all) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: Pied

    private var footer: some View {
        HStack {
            if grabber.captures > 0 {
                Text("\(grabber.captures) capture\(grabber.captures > 1 ? "s" : "")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Quitter") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
}
