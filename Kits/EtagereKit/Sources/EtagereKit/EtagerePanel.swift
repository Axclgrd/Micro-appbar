import AppKit
import Commun
import SwiftUI

/// Le panneau de réglages.
///
/// Il ne sert pas à se servir de l'étagère — ça se fait à la souris, sous
/// l'encoche. Il sert à savoir ce qu'elle garde quand la tablette est fermée,
/// et à reprendre la main quand un fichier a disparu.
struct EtagerePanel: View {
    let shelf: Shelf
    let reveal: () -> Void

    private var enabled: Binding<Bool> {
        Binding(get: { shelf.enabled }, set: { shelf.enabled = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            header
            if !shelf.items.isEmpty { list }
            Groupe {
                Toggle("Étagère active", isOn: enabled)
                    .toggleStyle(.switch)
            }
            footer
        }
        .padding(Espace.panneau)
    }

    private var header: some View {
        EnTete(
            symbole: shelf.items.isEmpty ? "tray" : "tray.full",
            teinte: shelf.items.isEmpty ? .secondary : .accentColor,
            titre: shelf.items.isEmpty
                ? "Étagère vide"
                : (shelf.items.count > 1 ? "\(shelf.items.count) objets" : "1 objet"),
            detail: "Sous l'encoche. Montez un fichier jusqu'en haut de l'écran, lâchez.")
    }

    private var list: some View {
        Groupe {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(shelf.items) { item in row(item) }
                }
            }
            .frame(maxHeight: 180)

            HStack {
                Spacer()
                Button("Tout retirer", role: .destructive) { shelf.removeAll() }
                    .controlSize(.small)
            }
        }
    }

    private func row(_ item: ShelfItem) -> some View {
        HStack(spacing: Espace.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 20, height: 20)
                .opacity(item.missing ? 0.4 : 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .strikethrough(item.missing)
                if item.missing {
                    Text("introuvable")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: Espace.xs)

            if !item.missing {
                Button {
                    ItemActions.reveal(item)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Afficher dans le Finder")
                .accessibilityLabel("Afficher dans le Finder")
            }

            Button {
                shelf.remove(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Retirer de l'étagère")
            .accessibilityLabel("Retirer de l'étagère")
        }
        .padding(.horizontal, Espace.xs)
        .padding(.vertical, 2)
        .survol()
        .contextMenu {
            if !item.missing {
                Button("Ouvrir") { ItemActions.open(item) }
                Button("Afficher dans le Finder") { ItemActions.reveal(item) }
            }
            Button("Copier le chemin") { ItemActions.copyPath(item) }
            Divider()
            Button("Retirer de l'étagère") { shelf.remove(item.id) }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            if let refusal = shelf.lastRefusal {
                Label(refusal, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Une image ou un texte sans fichier derrière lui est écrit dans un dépôt, pour qu'il soit encore là au prochain démarrage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Montrer la tablette", action: reveal)
                Button("Ouvrir le dépôt") {
                    let depot = Shelf.depot
                    try? FileManager.default.createDirectory(at: depot, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(depot)
                }
                Spacer()
            }
            .controlSize(.small)
        }
    }
}
