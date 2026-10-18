import AppKit
import CoreText
import SwiftUI

/// Ce que Claude a lu dans une capture.
///
/// Les champs sont exactement ceux du schéma imposé à la réponse
/// (`Typographer.schema`) : Claude Code valide la sortie contre lui avant de la
/// rendre, le décodage ne devine donc rien.
struct Verdict: Codable, Sendable, Hashable {
    /// Le texte lu dans l'image — il sert d'aperçu dans les polices installées.
    var text: String
    /// La famille typographique : « linéale géométrique », « didone »…
    var classification: String
    /// Du plus probable au moins probable.
    var candidates: [Candidate]
    /// Des polices libres proches, utiles quand la bonne est payante.
    var alternatives: [String]
    var note: String
    /// Comparée sur les vraies polices par un second appel à Claude. Rempli
    /// par l'app ; absent des analyses anciennes.
    var verified: Bool?

    var best: Candidate? { candidates.first }

    /// Une ligne de texte pour l'aperçu : la première de la capture, sinon un
    /// échantillon qui montre les lettres qui distinguent les familles.
    var sample: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Aa Gg Rr Qq 0123" : String(trimmed.prefix(48))
    }
}

struct Candidate: Codable, Sendable, Hashable, Identifiable {
    /// Le nom de famille seul, tel qu'il apparaît dans un menu de polices.
    var family: String
    var foundry: String
    var style: String
    /// Probabilité en pourcentage, de 0 à 100.
    var confidence: Int
    /// Les détails de lettres observés dans l'image.
    var evidence: String
    var license: License
    /// D'où vient le fichier qui a servi à la vérifier ; `nil` si elle n'a
    /// pas pu être dessinée. Rempli par l'app, jamais par Claude.
    var origin: Library.Origin?

    var id: String { family + "|" + style }
}

/// Les valeurs brutes restent en ASCII : elles font partie du schéma passé en
/// argument à Claude Code, et `Process` décompose les accents de ses arguments
/// (« è » devient « e » + accent combinant). Un « système » décomposé ne
/// correspond plus au « système » que Claude écrit, et la réponse est refusée.
enum License: String, Codable, Sendable, CaseIterable {
    case free
    case commercial
    case system
    case unknown

    /// Une valeur hors liste ne doit pas faire échouer toute l'analyse.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = License(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .free: "Libre"
        case .commercial: "Commerciale"
        case .system: "Système"
        case .unknown: "Licence inconnue"
        }
    }

    var color: Color {
        switch self {
        case .free: .green
        case .commercial: .orange
        case .system: .blue
        case .unknown: .secondary
        }
    }
}

/// Les polices qu'on peut montrer : installées sur ce Mac, ou téléchargées
/// pendant l'analyse pour être comparées.
///
/// Elles servent à une chose : montrer la proposition dans son propre dessin,
/// à côté de la capture, pour que l'œil tranche. On ne substitue jamais — un
/// aperçu rendu dans une autre police ferait croire à une ressemblance qui
/// n'existe pas. Introuvable, la police n'a pas d'aperçu, et c'est dit.
@MainActor
enum LocalFonts {

    static func isInstalled(_ candidate: Candidate) -> Bool {
        systemDesign(candidate.family) != nil || postScriptName(for: candidate) != nil
    }

    static func font(for candidate: Candidate, size: CGFloat) -> Font? {
        if let design = systemDesign(candidate.family) {
            return .system(size: size, weight: weight(candidate.style), design: design)
        }
        if let name = postScriptName(for: candidate) {
            return .custom(name, fixedSize: size)
        }
        guard let name = downloadedName(for: candidate) else { return nil }
        return .custom(name, fixedSize: size)
    }

    /// Le fichier téléchargé pendant l'analyse, s'il existe.
    static func downloaded(_ candidate: Candidate) -> URL? {
        Library.cached(family: candidate.family, style: candidate.style)
    }

    /// Copie la police téléchargée dans `~/Library/Fonts` : elle devient
    /// disponible dans toutes les apps, comme un double-clic dans Livre des
    /// polices — sans la fenêtre.
    @discardableResult
    static func install(_ candidate: Candidate) -> Bool {
        guard let file = downloaded(candidate) else { return false }
        let fonts = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Fonts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        let name = (postScriptName(in: file) ?? file.deletingPathExtension().lastPathComponent) + ".ttf"
        let target = fonts.appending(path: name)
        guard !FileManager.default.fileExists(atPath: target.path) else { return true }
        return (try? FileManager.default.copyItem(at: file, to: target)) != nil
    }

    /// Une police téléchargée n'est connue que de ce processus : on
    /// l'enregistre une fois, le temps de la session, pour pouvoir la nommer.
    private static var registered: [URL: String] = [:]

    private static func downloadedName(for candidate: Candidate) -> String? {
        guard let file = downloaded(candidate) else { return nil }
        if let name = registered[file] { return name }
        guard let name = postScriptName(in: file) else { return nil }
        CTFontManagerRegisterFontURLs([file] as CFArray, .process, true, nil)
        registered[file] = name
        return name
    }

    private static func postScriptName(in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let first = descriptors.first
        else { return nil }
        return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
    }

    /// Le nom PostScript du membre de la famille qui correspond au style.
    ///
    /// La liste est relue à chaque appel plutôt que gardée : une police qu'on
    /// installe après l'analyse doit apparaître dès qu'on revient sur la fiche.
    static func postScriptName(for candidate: Candidate) -> String? {
        let wanted = key(candidate.family)
        guard let family = NSFontManager.shared.availableFontFamilies.first(where: { key($0) == wanted }),
              let members = NSFontManager.shared.availableMembers(ofFontFamily: family)
        else { return nil }

        let named: [(postScript: String, style: String)] = members.compactMap { member in
            guard member.count > 1,
                  let postScript = member[0] as? String,
                  let style = member[1] as? String else { return nil }
            return (postScript, style.lowercased())
        }
        // Le style le plus long contenu dans celui demandé : « Bold Italic »
        // l'emporte sur « Bold », qui l'emporte sur rien.
        let style = candidate.style.lowercased()
        if let match = named.filter({ style.contains($0.style) }).max(by: { $0.style.count < $1.style.count }) {
            return match.postScript
        }
        let regular = ["regular", "roman", "book", "normal", "medium"]
        return named.first { regular.contains($0.style) }?.postScript ?? named.first?.postScript
    }

    /// Les polices du système ne figurent pas dans la liste des familles
    /// (leur nom interne commence par un point) : on les reconnaît par leur nom
    /// public et on passe par `Font.system`.
    private static func systemDesign(_ family: String) -> Font.Design? {
        let name = key(family)
        if name.hasPrefix("sfprorounded") { return .rounded }
        if name.hasPrefix("sfpro") || name.hasPrefix("sfcompact") || name == "sanfrancisco" { return .default }
        if name.hasPrefix("sfmono") { return .monospaced }
        if name == "newyork" { return .serif }
        return nil
    }

    private static func weight(_ style: String) -> Font.Weight {
        let style = style.lowercased()
        let table: [(String, Font.Weight)] = [
            ("ultralight", .ultraLight), ("extralight", .ultraLight), ("thin", .thin),
            ("light", .light), ("semibold", .semibold), ("demibold", .semibold),
            ("extrabold", .heavy), ("heavy", .heavy), ("black", .black),
            ("bold", .bold), ("medium", .medium),
        ]
        return table.first { style.contains($0.0) }?.1 ?? .regular
    }

    /// « Helvetica Neue », « helvetica-neue » et « HelveticaNeue » désignent
    /// la même famille.
    private static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}
