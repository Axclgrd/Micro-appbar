import Commun
import SwiftUI

struct PausePanel: View {
    @Bindable var pause: Pause

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            EnTete(symbole: symbole, teinte: teinte, titre: titre, detail: detail) {
                Toggle("Pause automatique", isOn: $pause.actif)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Groupe("Options") {
                option("Reprendre à la fin",
                       "Relance Apple Music une seconde après la libération du micro, seulement si c'est Pause qui l'avait coupée.",
                       isOn: $pause.reprise)
                Divider()
                option("AirPods et Bluetooth seulement",
                       "Un micro filaire ou USB ne dégrade pas le son : la musique continue.",
                       isOn: $pause.seulementBluetooth)
            }
            .disabled(!pause.actif)

            if pause.autorisationRefusee {
                Text("Trousse n'a pas le droit de piloter Musique. Réglages Système › Confidentialité et sécurité › Automatisation.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PiedDePanneau()
        }
        .padding(Espace.panneau)
    }

    private func option(_ titre: String, _ aide: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: Espace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                Text(aide)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Espace.s)
            Toggle(titre, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var symbole: String {
        switch pause.etat {
        case .musiqueEnPause: return "pause.circle.fill"
        case .microActif: return "mic.fill"
        case .enVeille: return "ear"
        case .desactive: return "pause.circle"
        }
    }

    private var teinte: Color {
        switch pause.etat {
        case .musiqueEnPause: return .orange
        case .microActif: return .red
        default: return .secondary
        }
    }

    private var titre: String {
        switch pause.etat {
        case .desactive: return "Désactivée"
        case .enVeille: return "En veille"
        case .microActif: return "Micro actif"
        case .musiqueEnPause: return "Musique en pause"
        }
    }

    private var detail: String {
        switch pause.etat {
        case .desactive: return "La musique n'est jamais touchée."
        case .enVeille: return "Entrée : \(pause.entree)"
        case .microActif: return "Rien ne jouait dans Musique."
        case .musiqueEnPause: return "Reprise dès que le micro se libère."
        }
    }
}
