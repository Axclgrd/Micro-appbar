import Commun
import Foundation

/// La suppression, et rien d'autre.
///
/// Séparée du reste pour une raison précise : c'est le seul endroit du
/// programme qui détruit quelque chose. Il tient en une page, et chaque garde
/// y est visible d'un coup d'œil.
enum Deleter {

    struct Report: Sendable {
        let removed: Set<String>
        let freed: Int64
        let failures: [String]
    }

    static func remove(_ findings: [Finding]) async -> Report {
        await Task.detached(priority: .userInitiated) {
            var removed: Set<String> = []
            var freed: Int64 = 0
            var failures: [String] = []

            for finding in findings {
                guard isSafe(finding.url) else {
                    failures.append("\(finding.url.path) : chemin refusé")
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: finding.url)
                    removed.insert(finding.id)
                    freed += finding.size
                } catch {
                    failures.append("\(finding.project)/\(finding.rule.directory) : \(error.localizedDescription)")
                }
            }
            return Report(removed: removed, freed: freed, failures: failures)
        }.value
    }

    /// Garde-fou de dernier recours.
    ///
    /// Une règle mal écrite, un lien symbolique, un chemin construit de travers
    /// et on efface un disque entier. On refuse donc tout chemin trop court
    /// pour être autre chose qu'une racine : « / », « /Volumes/X »,
    /// « /Users/quelqu-un ». La suppression demandée par l'utilisateur passe
    /// toujours par ici, sans exception.
    private static func isSafe(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        let components = standardized.pathComponents.filter { $0 != "/" }
        guard components.count >= 3 else { return false }

        // Ni un lien symbolique (on effacerait la cible), ni un fichier isolé.
        guard let values = try? standardized.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true
        else { return false }

        return true
    }
}
