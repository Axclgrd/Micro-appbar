import Observation
import Commun
import SwiftUI

/// Un groupe : une icône dans la barre du haut, un nom, et les outils qu'elle
/// contient. C'est l'unité que l'utilisateur compose.
struct MenuGroup: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var modules: [String]

    /// Le nom tel qu'on l'affiche. Le nom *stocké*, lui, a le droit d'être
    /// vide : c'est l'état normal d'un champ qu'on est en train de retaper.
    /// Substituer au moment de la saisie rendait l'effacement impossible — le
    /// champ se remplissait de « Sans nom » au dernier caractère supprimé.
    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Sans nom" : name
    }
}

/// La configuration de la barre : quels groupes existent, qui contient quoi,
/// et ce qui est volontairement masqué.
@MainActor
@Observable
final class Config {
    static let shared = Config()

    private(set) var groups: [MenuGroup] = []
    /// Les outils qu'on ne veut voir nulle part. Grab en est l'exemple : son
    /// raccourci suffit, une icône permanente serait une place prise pour rien.
    private(set) var hidden: Set<String> = []

    private static let key = "configuration"

    private init() {
        load()
        adopt()
    }

    // MARK: Lecture et écriture

    private struct Stored: Codable {
        var groups: [MenuGroup]
        var hidden: [String]
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else {
            groups = Self.starter
            hidden = ["grab"]
            save()
            return
        }
        groups = stored.groups
        hidden = Set(stored.hidden)
    }

    private func save() {
        let stored = Stored(groups: groups, hidden: Array(hidden))
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    /// Un module compilé depuis la dernière fois doit apparaître quelque part,
    /// sinon il serait invisible sans que rien ne le dise. Il rejoint le premier
    /// groupe, à charge pour l'utilisateur de le ranger.
    private func adopt() {
        let placed = Set(groups.flatMap(\.modules)).union(hidden)
        let orphans = Registry.shared.ids.filter { !placed.contains($0) }
        guard !orphans.isEmpty else { return }
        if groups.isEmpty {
            groups = [MenuGroup(name: "Trousse", symbol: "shippingbox", modules: orphans)]
        } else {
            groups[0].modules.append(contentsOf: orphans)
        }
        save()
    }

    /// Le rangement du premier lancement. Il n'est qu'une proposition — tout
    /// se déplace ensuite — mais il vaut mieux qu'une seule icône fourre-tout :
    /// les outils de la machine d'un côté, ceux du travail de l'autre.
    ///
    /// Grab commence masqué : son raccourci suffit, et c'est l'exemple même de
    /// l'outil qui n'a aucune raison d'occuper une place permanente.
    private static var starter: [MenuGroup] {
        [
            MenuGroup(name: "Machine", symbol: "gauge.with.dots.needle.33percent",
                      modules: ["fancontrole", "ejecter", "eveil"]),
            MenuGroup(name: "Travail", symbol: "wrench.and.screwdriver",
                      modules: ["ports", "purge", "bande", "etagere"]),
        ]
    }

    // MARK: Composition

    func modules(of group: MenuGroup) -> [Module] {
        group.modules.compactMap { Registry.shared.module($0) }
    }

    func group(containing id: String) -> MenuGroup? {
        groups.first { $0.modules.contains(id) }
    }

    func addGroup() {
        groups.append(MenuGroup(name: "Nouveau groupe", symbol: "square.grid.2x2", modules: []))
        save()
    }

    func removeGroup(_ group: MenuGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        // Les outils du groupe effacé ne disparaissent pas : ils passent en
        // masqués, où l'on peut les reprendre.
        hidden.formUnion(groups[index].modules)
        groups.remove(at: index)
        save()
    }

    func rename(_ group: MenuGroup, to name: String) {
        update(group) { $0.name = name }
    }

    func setSymbol(_ symbol: String, for group: MenuGroup) {
        update(group) { $0.symbol = symbol }
    }

    /// Déplace un outil vers un groupe, ou vers les masqués si `group` est nil.
    func place(_ moduleID: String, in group: MenuGroup?) {
        for index in groups.indices {
            groups[index].modules.removeAll { $0 == moduleID }
        }
        hidden.remove(moduleID)
        if let group, let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index].modules.append(moduleID)
        } else {
            hidden.insert(moduleID)
        }
        save()
    }

    func move(_ group: MenuGroup, by offset: Int) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let target = index + offset
        guard groups.indices.contains(target) else { return }
        groups.swapAt(index, target)
        save()
    }

    private func update(_ group: MenuGroup, _ change: (inout MenuGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        change(&groups[index])
        save()
    }
}
