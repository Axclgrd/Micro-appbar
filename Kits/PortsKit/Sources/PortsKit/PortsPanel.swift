import Commun
import SwiftUI

struct PortsPanel: View {
    @Bindable var module: PortsModule
    @Environment(\.accessibilityReduceMotion) private var reduireMouvement
    @State private var opened: String?
    @State private var showingQR: String?
    /// La ligne dont l'arrêt attend une confirmation.
    @State private var confirming: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            header
            if module.listeners.isEmpty {
                EtatVide(symbole: "network.slash",
                         titre: "Rien n'écoute",
                         detail: "Aucun serveur, aucun service, aucun port pris.")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(module.listeners) { listener in
                            row(listener)
                        }
                    }
                }
                .frame(maxHeight: 340)
            }
        }
        .padding(Espace.panneau)
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ports en écoute").font(.headline)
                if !module.listeners.isEmpty {
                    Text(module.listeners.count > 1
                         ? "\(module.listeners.count) ports pris"
                         : "1 port pris")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if module.scanning {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    module.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Relire les ports")
                .accessibilityLabel("Relire les ports")
            }
        }
    }

    // MARK: Ligne

    private func row(_ listener: Listener) -> some View {
        let isOpen = opened == listener.id

        return VStack(alignment: .leading, spacing: Espace.s) {
            Button {
                withAnimation(reduireMouvement ? nil : .snappy(duration: 0.18)) {
                    opened = isOpen ? nil : listener.id
                    if !isOpen { confirming = nil }
                }
            } label: {
                HStack(spacing: Espace.s) {
                    Text(String(listener.port))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(color(listener.verdict))
                        .frame(width: 52, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(listener.process)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(subtitle(listener))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Espace.xs)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Port \(listener.port), \(listener.process)")
            .accessibilityValue(isOpen ? "Détails affichés" : "Détails masqués")
            .accessibilityHint("Affiche ou masque les détails")

            if isOpen {
                detail(listener)
                    .padding(.horizontal, Espace.xs)
                    .padding(.bottom, Espace.xs)
            }
        }
        .padding(.horizontal, Espace.s)
        .padding(.vertical, 6)
        .background(isOpen ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: Espace.rayon))
        .survol(rayon: Espace.rayon)
    }

    // MARK: Détail

    @ViewBuilder
    private func detail(_ listener: Listener) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            // La conséquence d'abord : c'est elle qui décide d'arrêter ou non.
            Text(listener.note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !listener.directory.isEmpty, listener.directory != "/" {
                Text(listener.directory)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(listener.directory)
            }

            if confirming == listener.id {
                confirmation(listener)
            } else {
                HStack(spacing: Espace.s) {
                    Text("PID \(String(listener.pid))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if listener.verdict == .system {
                        Label("Non arrêtable", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        if module.url(for: listener) != nil {
                            Button {
                                showingQR = showingQR == listener.id ? nil : listener.id
                            } label: {
                                Label("Téléphone", systemImage: "qrcode")
                            }
                            .controlSize(.small)
                            .help("Afficher un QR code pour ouvrir ce site sur un téléphone")
                        }
                        Button(role: .destructive) {
                            // Arrêter une autre application coûte plus que
                            // libérer un port : on demande d'abord.
                            if listener.verdict == .care {
                                confirming = listener.id
                            } else {
                                module.stop(listener)
                            }
                        } label: {
                            Text("Arrêter")
                        }
                        .controlSize(.small)
                        .help("Arrêter le processus \(listener.process)")
                    }
                }
            }

            if showingQR == listener.id, let image = module.qr(for: listener),
               let text = module.url(for: listener) {
                VStack(spacing: Espace.s) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 132, height: 132)
                        .accessibilityLabel("QR code de \(text)")
                        .padding(Espace.s)
                        // Le blanc est voulu : un QR se lit mal sur fond sombre.
                        .background(.white, in: .rect(cornerRadius: Espace.s))
                    Text(text)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func confirmation(_ listener: Listener) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Text("Arrêter \(listener.process) ?")
                .font(.subheadline.weight(.medium))
            HStack {
                Spacer()
                Button("Annuler") { confirming = nil }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Arrêter", role: .destructive) {
                    confirming = nil
                    module.stop(listener)
                }
                .controlSize(.small)
            }
        }
    }

    private func subtitle(_ listener: Listener) -> String {
        var parts: [String] = []
        if let project = listener.project { parts.append(project) }
        parts.append(Format.age(listener.age))
        if listener.verdict != .yours { parts.append(listener.verdict.label) }
        return parts.joined(separator: " · ")
    }

    private func color(_ verdict: Verdict) -> Color {
        switch verdict {
        case .yours:  .accentColor
        case .care:   .orange
        case .system: .secondary
        }
    }
}
