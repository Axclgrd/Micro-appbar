import AppKit

/// Un objet posé sur la tablette.
///
/// L'étagère garde un *chemin*, pas une copie : poser un fichier ne le déplace
/// pas, ne le duplique pas, et le reprendre ne fait que rendre ce chemin à
/// l'app qui le reçoit. C'est ce qui permet d'y laisser un dossier de vingt
/// gigaoctets sans y penser.
public struct ShelfItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public internal(set) var url: URL
    public let addedAt: Date

    /// Un signet en plus du chemin. Il coûte quelques octets et rattrape le cas
    /// le plus fréquent de « fichier disparu » : un fichier simplement renommé
    /// ou rangé ailleurs entre deux sessions.
    var bookmark: Data?

    /// Vrai quand plus rien ne répond ni au chemin ni au signet. L'objet reste
    /// visible, barré : le faire disparaître tout seul laisserait croire à un
    /// bug de l'étagère plutôt qu'à une suppression.
    public internal(set) var missing = false

    /// Vrai pendant le quart de seconde qui suit la pose, le temps du rebond.
    var landing = false

    public var name: String { url.lastPathComponent }

    init(url: URL) {
        id = UUID()
        self.url = url
        addedAt = Date()
        bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        landing = true
    }

    init(id: UUID, url: URL, addedAt: Date, bookmark: Data?) {
        self.id = id
        self.url = url
        self.addedAt = addedAt
        self.bookmark = bookmark
    }

    /// Vérifie que le fichier est toujours là, et le retrouve s'il a bougé.
    mutating func verify() {
        if FileManager.default.fileExists(atPath: url.path) {
            missing = false
            return
        }
        var stale = false
        if let bookmark,
           let found = try? URL(resolvingBookmarkData: bookmark, options: [],
                                relativeTo: nil, bookmarkDataIsStale: &stale),
           FileManager.default.fileExists(atPath: found.path) {
            url = found
            missing = false
            if stale {
                self.bookmark = try? found.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            return
        }
        missing = true
    }
}

/// Ce qui est écrit sur le disque entre deux sessions.
struct StoredItem: Codable {
    let id: UUID
    let path: String
    let addedAt: Date
    let bookmark: Data?

    init(_ item: ShelfItem) {
        id = item.id
        path = item.url.path
        addedAt = item.addedAt
        bookmark = item.bookmark
    }

    var item: ShelfItem {
        ShelfItem(id: id, url: URL(fileURLWithPath: path), addedAt: addedAt, bookmark: bookmark)
    }
}
