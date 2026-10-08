import Commun
import SwiftUI

struct PortsPanel: View {
    @Bindable var module: PortsModule
    @State private var opened: String?
    @State private var showingQR: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if module.listeners.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(module.listeners) { listener in
                            row(listener)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Ports en écoute")
                .font(.callout.weight(.semibold))
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
                .help("Relire")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("Rien n'écoute.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Aucun serveur, aucun service, aucun port pris.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func row(_ listener: Listener) -> some View {
        let isOpen = opened == listener.id

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(String(listener.port))
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(color(listener.verdict))
                    .frame(width: 48, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(listener.process)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle(listener))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.snappy(duration: 0.18)) {
                    opened = isOpen ? nil : listener.id
                }
            }

            if isOpen {
                detail(listener)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isOpen ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 7))
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func detail(_ listener: Listener) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(listener.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !listener.directory.isEmpty, listener.directory != "/" {
                Text(listener.directory)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            HStack(spacing: 6) {
                Text("PID \(listener.pid)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)

                Spacer()

                if listener.verdict == .system {
                    Text("non arrêtable")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    if module.url(for: listener) != nil {
                        Button {
                            showingQR = showingQR == listener.id ? nil : listener.id
                        } label: {
                            Label("Téléphone", systemImage: "qrcode")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    Button {
                        module.stop(listener)
                    } label: {
                        Text("Arrêter").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(listener.verdict == .care ? Color.orange : Color.red)
                }
            }

            if showingQR == listener.id, let image = module.qr(for: listener),
               let text = module.url(for: listener) {
                VStack(spacing: 5) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 132, height: 132)
                        .padding(6)
                        .background(.white, in: .rect(cornerRadius: 6))
                    Text(text)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
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
