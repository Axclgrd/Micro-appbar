import Commun
import SwiftUI

struct PanelView: View {
    @Bindable var grabber: Grabber

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.l) {
            EnTete(symbole: "text.viewfinder",
                   titre: "Texte à l'écran",
                   detail: grabber.status ?? "Sélectionne une zone, le texte part dans le presse-papiers.")
            obstacles
            action
            if grabber.text != nil {
                result
            }
            options
            footer
        }
        .padding(Espace.panneau)
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
            VStack(alignment: .leading, spacing: Espace.s) {
                Label("Enregistrement de l'écran requis", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text("macOS n'a pas laissé \(Grabber.host) lire l'écran. Autorise-le dans les réglages, puis relance \(Grabber.host).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Espace.s) {
                    Button("Ouvrir les réglages") { grabber.requestPermission() }
                        .controlSize(.small)
                    Button("Réessayer") { grabber.clearDenial() }
                        .controlSize(.small)
                }
                // C'est l'app *hôte* qu'il faut cocher, pas l'outil : chercher « Grab »
                // dans la liste alors que c'est Trousse qui capture, c'est chercher une
                // ligne qui n'existe pas.
                Text("Si \(Grabber.host) est déjà coché, « Réessayer » suffit.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Espace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
        } else if !grabber.hotkeyWorks {
            Label("Ce raccourci est déjà pris par une autre app. Choisis-en un autre dans les réglages ci-dessous.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Capture

    // Une seule action principale : Capturer. Le raccourci reste à côté,
    // en discret, pour qu'on le retienne.
    private var action: some View {
        HStack(spacing: Espace.m) {
            Button {
                Task { await grabber.capture() }
            } label: {
                Label("Capturer", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(grabber.working)
            .help("Sélectionner une zone de l'écran")

            if grabber.working {
                ProgressView().controlSize(.small)
            } else {
                Text(grabber.shortcut.label)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .help("Raccourci global")
                    .accessibilityLabel("Raccourci \(grabber.shortcut.label)")
            }
        }
    }

    // MARK: Résultat

    private var result: some View {
        Groupe("Dernière capture") {
            ScrollView {
                Text(grabber.text ?? "")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 150)

            HStack(spacing: Espace.s) {
                Button("Recopier") { grabber.copy() }
                    .controlSize(.small)
                Button("Effacer", role: .destructive) { grabber.forget() }
                    .controlSize(.small)
                Spacer()
            }
        }
    }

    // MARK: Réglages

    private var options: some View {
        Groupe("Réglages") {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Correction linguistique", isOn: $grabber.languageCorrection)
                Text(grabber.languageCorrection
                     ? "Vision corrige les mots abîmés, et réécrit parfois un identifiant ou une commande."
                     : "Texte rendu tel quel, idéal pour du code et des messages d'erreur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Icône dans la barre des menus", isOn: $grabber.showIcon)
                if grabber.showIcon {
                    Text("Sans icône, le raccourci continue de marcher. Relancer \(Grabber.host) la fait revenir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Text("Raccourci")
                Spacer()
                Picker("Raccourci", selection: $grabber.shortcut) {
                    ForEach(Shortcut.all) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: Pied

    private var footer: some View {
        PiedDePanneau {
            if grabber.captures > 0 {
                Text("\(grabber.captures) capture\(grabber.captures > 1 ? "s" : "")")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
