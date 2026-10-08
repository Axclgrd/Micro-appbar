import AppKit
import Commun
import Observation
import UniformTypeIdentifiers

/// L'étagère : ce qui est posé, et dans quel état est la tablette.
///
/// Un seul objet par processus. Deux étagères, ce serait deux tablettes sous la
/// même encoche, chacune ignorant ce que l'autre garde.
@MainActor
@Observable
public final class Shelf {
    public static let shared = Shelf()

    /// Les trois états de la tablette, et rien entre les deux.
    ///
    /// `awake` n'est pas « à moitié ouverte » : c'est l'encoche qui s'épaissit
    /// de trois points parce qu'un glisser est en cours quelque part. La
    /// tablette, elle, est encore entièrement rentrée.
    public enum Phase: Equatable { case closed, awake, open }

    public private(set) var items: [ShelfItem] = []
    public internal(set) var phase: Phase = .closed

    /// L'index où la place se creuse sous le curseur. `nil` quand aucun glisser
    /// ne survole la tablette.
    var insertion: Int?

    /// L'objet qu'on est en train de reprendre : il se soulève, les autres
    /// referment le trou.
    var lifted: ShelfItem.ID?

    /// Le dernier refus, à afficher dans les réglages. On ne le crie pas sur la
    /// tablette : une étagère qui affiche des messages d'erreur n'est plus une
    /// étagère.
    public private(set) var lastRefusal: String?

    public var enabled: Bool {
        didSet { Shared.defaults.set(enabled, forKey: "etagere.enabled") }
    }

    private init() {
        // Le réglage n'existe pas au premier lancement : l'étagère est alors
        // active, sinon l'outil serait installé et invisible.
        enabled = Shared.defaults.object(forKey: "etagere.enabled") as? Bool ?? true
        load()
    }

    // MARK: - Poser

    /// Lit un presse-papier de glisser et pose ce qu'il contient.
    ///
    /// Rend le nombre d'objets réellement posés — zéro quand le glisser
    /// n'apportait rien qu'on sache garder.
    @discardableResult
    func accept(_ pasteboard: NSPasteboard, at index: Int) -> Int {
        let urls = harvest(pasteboard)
        guard !urls.isEmpty else {
            lastRefusal = "Ce glisser n'apportait ni fichier, ni image, ni texte."
            return 0
        }
        lastRefusal = nil
        var at = min(max(index, 0), items.count)
        var added = 0
        for url in urls {
            // Reposer ce qui est déjà là ne crée pas de doublon : ça le remet
            // simplement là où on vient de viser.
            if let existing = items.firstIndex(where: { $0.url == url }) {
                let moved = items.remove(at: existing)
                if existing < at { at -= 1 }
                items.insert(moved, at: at)
            } else {
                items.insert(ShelfItem(url: url), at: at)
            }
            at += 1
            added += 1
        }
        // La capacité se réduit par la fin : ce qu'on vient de poser est ce
        // qu'on cherche, ce qui dort là depuis hier est ce qu'on a oublié.
        while items.count > Metric.capacity {
            let oldest = items.indices.max(by: { items[$0].addedAt > items[$1].addedAt })
            items.remove(at: oldest ?? items.count - 1)
        }
        save()
        warm()
        clearLanding()
        return added
    }

    /// Prépare les vignettes avant qu'on ouvre la tablette.
    ///
    /// QuickLook met quelques dizaines de millisecondes par fichier. Sans ce
    /// préchauffage, la première ouverture après un démarrage montre des icônes
    /// de document génériques qui se changent en aperçus sous les yeux — on
    /// croit à un chargement raté plutôt qu'à une étagère.
    private func warm() {
        let urls = items.filter { !$0.missing }.map(\.url)
        Task { for url in urls { _ = await Thumbs.load(url) } }
    }

    /// Efface le drapeau de rebond après le temps de l'animation, pour qu'un
    /// objet ne rebondisse pas une seconde fois si la vue se reconstruit.
    private func clearLanding() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            for index in items.indices where items[index].landing {
                items[index].landing = false
            }
        }
    }

    func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func removeAll() {
        items.removeAll()
        save()
    }

    /// Relit l'existence de chaque objet. Appelé à l'ouverture de la tablette :
    /// un fichier jeté à la corbeille entre-temps doit être signalé, pas
    /// découvert au moment où on le reprend.
    func verifyAll() {
        for index in items.indices { items[index].verify() }
    }

    // MARK: - Ce que le glisser apporte

    /// Extrait des URL de fichiers d'un presse-papier de glisser, en
    /// matérialisant ce qui n'en est pas.
    ///
    /// Un choix a été fait ici : une image ou un texte venus d'un navigateur
    /// n'ont *pas* de fichier derrière eux, et refuser le glisser casserait la
    /// promesse de l'outil — « on attrape quelque chose, on monte, on lâche ».
    /// Ils sont donc écrits dans un dépôt, sous « Application Support », dont
    /// le chemin est affiché dans les réglages. Une étagère qui garde des
    /// choses qui n'existent nulle part serait pire : au premier redémarrage
    /// elle serait vide sans explication.
    private func harvest(_ pasteboard: NSPasteboard) -> [URL] {
        let fileOption: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOption) as? [URL],
           !files.isEmpty {
            return files
        }

        if let links = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let link = links.first, link.scheme != "file",
           let file = writeWebloc(link) {
            return [file]
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first, let file = writePNG(image) {
            return [file]
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let file = writeText(text) {
            return [file]
        }

        return []
    }

    /// Le dossier où atterrit ce qui n'avait pas de fichier.
    public static var depot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Étagère/Dépôt", isDirectory: true)
    }

    private func makeDepot() -> URL? {
        let url = Self.depot
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            lastRefusal = "Impossible de créer le dépôt : \(error.localizedDescription)"
            return nil
        }
    }

    /// Un nom daté, lisible, et unique sans compteur : deux glissers dans la
    /// même seconde sont un cas qu'on peut ignorer.
    private func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "yyyy-MM-dd HH'h'mm'm'ss"
        return formatter.string(from: Date())
    }

    private func writePNG(_ image: NSImage) -> URL? {
        guard let depot = makeDepot(),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = depot.appendingPathComponent("Image \(stamp()).png")
        return (try? png.write(to: url)) == nil ? nil : url
    }

    private func writeText(_ text: String) -> URL? {
        guard let depot = makeDepot() else { return nil }
        let url = depot.appendingPathComponent("Texte \(stamp()).txt")
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) == nil ? nil : url
    }

    /// Un lien web devient un `.webloc` — le format que le Finder sait ouvrir,
    /// plutôt qu'un fichier texte contenant une adresse.
    private func writeWebloc(_ link: URL) -> URL? {
        guard let depot = makeDepot(),
              let data = try? PropertyListSerialization.data(
                fromPropertyList: ["URL": link.absoluteString], format: .xml, options: 0)
        else { return nil }
        let host = link.host ?? "Lien"
        let url = depot.appendingPathComponent("\(host) \(stamp()).webloc")
        return (try? data.write(to: url)) == nil ? nil : url
    }

    // MARK: - Entre deux sessions

    private func save() {
        guard let data = try? JSONEncoder().encode(items.map(StoredItem.init)) else { return }
        Shared.defaults.set(data, forKey: "etagere.items")
    }

    private func load() {
        guard let data = Shared.defaults.data(forKey: "etagere.items"),
              let stored = try? JSONDecoder().decode([StoredItem].self, from: data) else { return }
        items = stored.map(\.item)
        verifyAll()
        warm()
    }
}
