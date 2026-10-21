import Foundation

/// Quelles apps sont touchées par un ensemble de fichiers modifiés.
///
/// Une app dépend de son dossier et des bibliothèques de `Kits/` qu'elle
/// déclare dans son `Package.swift`, directement ou par une autre
/// bibliothèque (FanKit → SMCKit). On lit ces fichiers plutôt que d'en tenir
/// une liste : un nouveau Kit est pris en compte sans toucher à ce code.
enum Impact {
    /// (dossier, nom du bundle). Trousse en dernier : elle se remplace
    /// elle-même, et tout le reste doit être fini avant.
    static let apps: [(dossier: String, nom: String)] = [
        ("fancontrole", "FanControl"), ("ejecter", "Ejecter"), ("purge", "Purge"),
        ("eveil", "Eveil"), ("grab", "Grab"), ("fonte", "Fonte"), ("jauge", "Jauge"),
        ("ports", "Ports"), ("bande", "Bande"), ("etagere", "Etagere"),
        ("trousse", "Trousse"),
    ]

    static func nom(_ dossier: String) -> String {
        apps.first { $0.dossier == dossier }?.nom ?? dossier
    }

    private static func chemins(dans package: URL) -> [String] {
        guard let texte = try? String(contentsOf: package, encoding: .utf8),
              let regex = try? NSRegularExpression(
                pattern: #"path:\s*"\.\./(?:Kits/)?([A-Za-z0-9_\-]+)""#)
        else { return [] }
        let plage = NSRange(texte.startIndex..., in: texte)
        return regex.matches(in: texte, range: plage).compactMap {
            Range($0.range(at: 1), in: texte).map { String(texte[$0]) }
        }
    }

    /// Pour chaque app, l'ensemble des Kits qu'elle compile (transitif).
    static func dependances(racine: URL) -> [String: Set<String>] {
        let kitsDir = racine.appendingPathComponent("Kits")
        var directes: [String: [String]] = [:]
        let noms = (try? FileManager.default.contentsOfDirectory(atPath: kitsDir.path)) ?? []
        for kit in noms {
            directes[kit] = chemins(dans: kitsDir.appendingPathComponent("\(kit)/Package.swift"))
        }
        var resultat: [String: Set<String>] = [:]
        for (dossier, _) in apps {
            var vus = Set<String>()
            var pile = chemins(dans: racine.appendingPathComponent("\(dossier)/Package.swift"))
            while let kit = pile.popLast() {
                guard vus.insert(kit).inserted else { continue }
                pile.append(contentsOf: directes[kit] ?? [])
            }
            resultat[dossier] = vus
        }
        return resultat
    }

    /// Les dossiers d'apps à reconstruire pour ces fichiers, dans l'ordre de
    /// `apps`. Les `.md` ne changent aucun binaire.
    static func touchees(par fichiers: [String], racine: URL) -> [String] {
        let deps = dependances(racine: racine)
        var touchees = Set<String>()
        for fichier in fichiers where !fichier.hasSuffix(".md") {
            let parties = fichier.split(separator: "/").map(String.init)
            guard let premier = parties.first else { continue }
            if premier == "Kits", parties.count > 2 {
                for (dossier, kits) in deps where kits.contains(parties[1]) { touchees.insert(dossier) }
            } else if apps.contains(where: { $0.dossier == premier }) {
                touchees.insert(premier)
            }
        }
        return apps.map(\.dossier).filter(touchees.contains)
    }

    /// On ne reconstruit que ce qui est installé : une mise à jour ne doit pas
    /// ajouter une app que l'utilisateur n'a pas voulue.
    static func installees(_ dossiers: [String],
                           applications: URL = URL(fileURLWithPath: "/Applications")) -> [String] {
        dossiers.filter {
            FileManager.default.fileExists(
                atPath: applications.appendingPathComponent("\(nom($0)).app").path)
        }
    }
}
