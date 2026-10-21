import Commun
import SwiftUI

struct NuitPanel: View {
    @Bindable var nuit: Nuit

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            EnTete(symbole: symbole, teinte: teinte, titre: titre, detail: detail) {
                Toggle("Stabilisateur audio", isOn: $nuit.actif)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Groupe("Réglage") {
                Picker("Préréglage", selection: $nuit.preset) {
                    ForEach(Nuit.Preset.allCases) { Text($0.titre).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(nuit.preset.aide)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: Espace.xs) {
                    HStack {
                        Text("Niveau cible")
                        Spacer()
                        Text("\(Int(nuit.cible)) dB")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $nuit.cible, in: -40 ... -12, step: 1) {
                        Text("Niveau cible")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.wave.1").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3").accessibilityHidden(true)
                    }
                    .controlSize(.small)
                    Text("Plus bas, plus le son est écrasé tôt : un réglage bas aplatit davantage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if nuit.actif {
                Groupe("Mesure") {
                    Ligne("Entrée", db(nuit.niveauEntree))
                    Ligne("Sortie", db(nuit.niveauSortie))
                    Ligne("Réduction", nuit.reduction > 0.5 ? "−\(Int(nuit.reduction.rounded())) dB" : "—")
                    Ligne("Retard ajouté", retard, aide: "Sortie : \(nuit.sortie)")
                }
            }

            if !nuit.avertissement.isEmpty {
                Text(nuit.avertissement)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PiedDePanneau()
        }
        .padding(Espace.panneau)
    }

    private func db(_ x: Float) -> String { x <= -100 ? "—" : "\(Int(x.rounded())) dB" }

    private var retard: String {
        let ms = nuit.latenceMs + nuit.latenceMaterielMs
        return ms > 0 ? "≈ \(Int(ms.rounded())) ms" : "—"
    }

    private var symbole: String {
        switch nuit.etat {
        case .desactive: return "moon.stars"
        case .erreur: return "exclamationmark.triangle.fill"
        default: return "moon.stars.fill"
        }
    }

    private var teinte: Color {
        switch nuit.etat {
        case .actif: return .indigo
        case .erreur: return .orange
        default: return .secondary
        }
    }

    private var titre: String {
        switch nuit.etat {
        case .desactive: return "Désactivé"
        case .demarrage: return "Démarrage…"
        case .enAttente: return "En attente de son"
        case .actif: return "Son lissé"
        case .erreur: return "Arrêté"
        }
    }

    private var detail: String {
        switch nuit.etat {
        case .desactive: return "Le son du Mac n'est pas touché."
        case .demarrage: return "Le son d'origine revient si quoi que ce soit échoue."
        case .enAttente: return "Aucune app ne joue en ce moment."
        case .actif: return "Les pics sont écrasés, le niveau est stabilisé."
        case .erreur(let m): return m
        }
    }
}
