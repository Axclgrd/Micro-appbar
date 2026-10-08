import AppKit
import SwiftUI

/// Le panneau de réglages.
///
/// Il ne sert pas à se servir de l'étagère — ça se fait à la souris, sous
/// l'encoche. Il sert à savoir ce qu'elle garde quand la tablette est fermée,
/// et à reprendre la main quand un fichier a disparu.
struct EtagerePanel: View {
    let shelf: Shelf
    let reveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if shelf.items.isEmpty { empty } else { list }
            Divider()
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: shelf.items.isEmpty ? "tray" : "tray.full")
                .font(.title2)
                .foregroundStyle(shelf.items.isEmpty ? Color.secondary : .green)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(shelf.items.isEmpty ? "Étagère vide" : "\(shelf.items.count) objet\(shelf.items.count > 1 ? "s" : "")")
                    .font(.headline)
                Text("Sous l'encoche. Montez un fichier jusqu'en haut de l'écran, lâchez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var empty: some View {
        Toggle("Étagère active", isOn: Binding(
            get: { shelf.enabled },
            set: { shelf.enabled = $0 }))
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(shelf.items) { item in row(item) }
                }
            }
            .frame(maxHeight: 180)

            HStack {
                Toggle("Active", isOn: Binding(
                    get: { shelf.enabled },
                    set: { shelf.enabled = $0 }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button("Tout retirer") { shelf.removeAll() }
                    .controlSize(.small)
            }
        }
    }

    private func row(_ item: ShelfItem) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .opacity(item.missing ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .strikethrough(item.missing)
                if item.missing {
                    Text("introuvable")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 4)

            if !item.missing {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Afficher dans le Finder")
            }

            Button {
                shelf.remove(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Retirer de l'étagère")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let refusal = shelf.lastRefusal {
                Text(refusal)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Une image ou un texte sans fichier derrière lui est écrit dans un dépôt, pour qu'il soit encore là au prochain démarrage.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Montrer la tablette", action: reveal)
                    .controlSize(.small)
                Spacer()
            }
            Button("Ouvrir le dépôt") {
                let depot = Shelf.depot
                try? FileManager.default.createDirectory(at: depot, withIntermediateDirectories: true)
                NSWorkspace.shared.open(depot)
            }
            .controlSize(.small)
        }
    }
}
