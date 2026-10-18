import AppKit
import CoreText

/// Les polices qu'on peut réellement dessiner : celles du Mac, et celles
/// qu'on télécharge librement chez Google Fonts et Fontshare.
///
/// Claude reconnaît une police de mémoire ; ici, on la retrouve en vrai. Une
/// proposition qu'on peut dessiner peut être comparée lettre à lettre à la
/// capture — c'est ce qui sépare « ressemble à Poppins » de « c'est Poppins ».
/// Les polices payantes (Gilroy, Aeonik…) restent hors d'atteinte : elles
/// gardent le seul jugement de Claude, et la fiche le dit.
enum Library {

    enum Origin: String, Codable, Sendable {
        case installed, google, fontshare

        var label: String {
            switch self {
            case .installed: "Installée"
            case .google: "Google Fonts"
            case .fontshare: "Fontshare"
            }
        }
    }

    /// Une police retrouvée : de quoi la dessiner, et d'où elle vient.
    struct Face: @unchecked Sendable {
        let family: String
        let weight: Int
        let italic: Bool
        let origin: Origin
        /// Trouvée par le tri visuel, et non proposée par Claude.
        var screened = false
        /// Le fichier téléchargé ; `nil` pour une police du Mac.
        let file: URL?
        let font: CTFont
    }

    // MARK: Recherche

    /// Bloquant (réseau) : à appeler hors du fil principal.
    static func face(family: String, style: String) -> Face? {
        let (weight, italic) = Style.parse(style)
        if let face = installed(family: family, weight: weight, italic: italic) { return face }
        if let face = google(family: family, weight: weight, italic: italic) { return face }
        return fontshare(family: family, weight: weight, italic: italic)
    }

    /// Un fichier déjà téléchargé pour cette famille, sans réseau : c'est ce
    /// qui donne un aperçu aux polices libres qu'on n'a pas installées.
    static func cached(family: String, style: String) -> URL? {
        let (weight, italic) = Style.parse(style)
        let prefix = key(family) + "-"
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "ttf" }
            .compactMap { file -> (URL, Int)? in
                let stem = file.deletingPathExtension().lastPathComponent.dropFirst(prefix.count)
                let isItalic = stem.hasSuffix("i")
                guard let w = Int(stem.trimmingCharacters(in: CharacterSet(charactersIn: "i"))) else { return nil }
                return (file, abs(w - weight) + (isItalic == italic ? 0 : 1000))
            }
            .min { $0.1 < $1.1 }?.0
    }

    /// Le bassin du tri visuel : toutes les polices du Mac et tout
    /// Fontshare, chacune à trois graisses autour de celle estimée.
    ///
    /// La graisse compte : une Clash Display composée en 700 au lieu de 600
    /// ne se superposait plus, et le tri la perdait. Trois essais par famille
    /// rattrapent une estimation à cent près. Fontshare se télécharge une
    /// fois, en fichiers variables quand il en existe — un fichier par famille
    /// pour toutes les graisses — puis se lit sur le disque.
    static func pool(weight: Int, italic: Bool) -> [Face] {
        let weights = [weight - 100, weight, weight + 100].filter { (100...900).contains($0) }
        let installedNames = (CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
            .filter { !$0.hasPrefix(".") }
        let fontshareNames = Catalog.fontshare().values.map(\.family)
        let jobs = (installedNames.map { ($0, true) } + fontshareNames.map { ($0, false) })
            .flatMap { name, local in weights.map { (name, local, $0) } }

        let slots = Slots(count: jobs.count)
        // Seize à la fois : assez pour que le premier téléchargement de
        // Fontshare ne traîne pas, pas assez pour ressembler à une attaque.
        let gate = DispatchSemaphore(value: 16)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            gate.wait(); defer { gate.signal() }
            let (name, local, weight) = jobs[index]
            slots.set(index, local
                ? installed(family: name, weight: weight, italic: italic)
                : fontshare(family: name, weight: weight, italic: italic, download: weight == weights[weights.count / 2]))
        }
        // Une famille sans graisses intermédiaires rend trois fois la même :
        // une seule suffit.
        var seen = Set<String>()
        return slots.values.compactMap { $0 }.filter {
            seen.insert("\(key($0.family))-\(CTFontCopyPostScriptName($0.font))-\($0.weight)").inserted
        }
    }

    final class Slots: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var values: [Face?]
        init(count: Int) { values = Array(repeating: nil, count: count) }
        func set(_ index: Int, _ face: Face?) {
            lock.lock(); values[index] = face; lock.unlock()
        }
    }

    // MARK: Polices du Mac

    private static func installed(family: String, weight: Int, italic: Bool) -> Face? {
        if let system = systemFace(family: family, weight: weight, italic: italic) { return system }

        let wanted = key(family)
        // CoreText plutôt que NSFontManager : on est hors du fil principal.
        let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        guard let name = families.first(where: { key($0) == wanted }) else { return nil }
        let base = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: name] as CFDictionary)
        let members = CTFontDescriptorCreateMatchingFontDescriptors(base, nil) as? [CTFontDescriptor] ?? []
        let best = members.min { distance($0, weight, italic) < distance($1, weight, italic) }
        guard let best else { return nil }
        return Face(family: name, weight: weight, italic: italic, origin: .installed, file: nil,
                    font: CTFontCreateWithFontDescriptor(best, 72, nil))
    }

    /// Les polices d'Apple ne sont pas listées sous leur nom public : elles
    /// passent par les API de la police système.
    private static func systemFace(family: String, weight: Int, italic: Bool) -> Face? {
        let name = key(family)
        let design: NSFontDescriptor.SystemDesign
        if name.hasPrefix("sfprorounded") { design = .rounded }
        else if name.hasPrefix("sfmono") { design = .monospaced }
        else if name == "newyork" { design = .serif }
        else if name.hasPrefix("sfpro") || name.hasPrefix("sfcompact") || name == "sanfrancisco" { design = .default }
        else { return nil }

        var descriptor = NSFont.systemFont(ofSize: 72, weight: nsWeight(weight)).fontDescriptor
        descriptor = descriptor.withDesign(design) ?? descriptor
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        guard let font = NSFont(descriptor: descriptor, size: 72) else { return nil }
        return Face(family: family, weight: weight, italic: italic, origin: .installed, file: nil, font: font as CTFont)
    }

    private static func distance(_ descriptor: CTFontDescriptor, _ weight: Int, _ italic: Bool) -> Int {
        let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
        let symbolic = (traits[kCTFontSymbolicTrait] as? UInt32) ?? 0
        let isItalic = symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0
        let isCondensed = symbolic & CTFontSymbolicTraits.traitCondensed.rawValue != 0
        let w = Style.css(fromTrait: (traits[kCTFontWeightTrait] as? CGFloat) ?? 0)
        // Une variante étroite n'est jamais choisie par défaut : elle
        // fausserait la comparaison avec un texte de chasse normale.
        return abs(w - weight) + (isItalic == italic ? 0 : 1000) + (isCondensed ? 500 : 0)
    }

    private static func nsWeight(_ css: Int) -> NSFont.Weight {
        switch css {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }

    // MARK: Google Fonts

    private static func google(family: String, weight: Int, italic: Bool) -> Face? {
        guard let entry = Catalog.google()[key(family)] else { return nil }
        let variants = entry.variants.compactMap { variant -> (Int, Bool)? in
            let isItalic = variant.hasSuffix("i")
            guard let w = Int(variant.trimmingCharacters(in: CharacterSet(charactersIn: "i"))) else { return nil }
            return (w, isItalic)
        }
        guard let chosen = variants.min(by: {
            abs($0.0 - weight) + ($0.1 == italic ? 0 : 1000) < abs($1.0 - weight) + ($1.1 == italic ? 0 : 1000)
        }) else { return nil }

        let file = folder.appending(path: "\(key(entry.family))-\(chosen.0)\(chosen.1 ? "i" : "").ttf")
        if !FileManager.default.fileExists(atPath: file.path) {
            let axes = chosen.1 ? "ital,wght@1,\(chosen.0)" : "wght@\(chosen.0)"
            let name = entry.family.replacingOccurrences(of: " ", with: "+")
            // Un client ancien reçoit des TrueType ; un navigateur, du WOFF2.
            guard let css = Network.text("https://fonts.googleapis.com/css2?family=\(name):\(axes)", agent: "Wget/1.21"),
                  let url = firstTrueType(in: css),
                  Network.download(url, to: file)
            else { return nil }
        }
        return load(file, family: entry.family, weight: chosen.0, italic: chosen.1, origin: .google)
    }

    // MARK: Fontshare

    /// `download` à faux : seulement ce qui est déjà sur le disque, pour que
    /// les essais de graisse voisins ne multiplient pas les téléchargements.
    private static func fontshare(family: String, weight: Int, italic: Bool, download: Bool = true) -> Face? {
        guard let entry = Catalog.fontshare()[key(family)] else { return nil }

        // Un fichier variable couvre toutes les graisses : on l'instancie à
        // la graisse exacte.
        if !italic, let variable = entry.variable {
            let file = folder.appending(path: "\(key(entry.family))-variable.ttf")
            let present = FileManager.default.fileExists(atPath: file.path)
            let source = variable.hasPrefix("//") ? "https:" + variable : variable
            if present || (download && URL(string: source + ".ttf").map { Network.download($0, to: file) } == true),
               let face = load(file, family: entry.family, weight: weight, italic: false, origin: .fontshare) {
                let weighted = CTFontDescriptorCreateCopyWithVariation(
                    CTFontCopyFontDescriptor(face.font), 0x7767_6874 as CFNumber, CGFloat(weight))
                return Face(family: entry.family, weight: weight, italic: false, origin: .fontshare, file: file,
                            font: CTFontCreateWithFontDescriptor(weighted, 72, nil))
            }
        }

        guard let style = entry.styles.min(by: {
                  abs($0.weight - weight) + ($0.italic == italic ? 0 : 1000) < abs($1.weight - weight) + ($1.italic == italic ? 0 : 1000)
              })
        else { return nil }

        let file = folder.appending(path: "\(key(entry.family))-\(style.weight)\(style.italic ? "i" : "").ttf")
        if !FileManager.default.fileExists(atPath: file.path) {
            guard download else { return nil }
            let source = style.file.hasPrefix("//") ? "https:" + style.file : style.file
            guard let url = URL(string: source + ".ttf"), Network.download(url, to: file) else { return nil }
        }
        return load(file, family: entry.family, weight: style.weight, italic: style.italic, origin: .fontshare)
    }

    // MARK: Fichiers

    static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Micro-app/Fonte/Polices", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func load(_ file: URL, family: String, weight: Int, italic: Bool, origin: Origin) -> Face? {
        guard let data = try? Data(contentsOf: file),
              let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let first = descriptors.first
        else {
            // Un fichier illisible ne doit pas bloquer les essais suivants.
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return Face(family: family, weight: weight, italic: italic, origin: origin, file: file,
                    font: CTFontCreateWithFontDescriptor(first, 72, nil))
    }

    private static func firstTrueType(in css: String) -> URL? {
        guard let range = css.range(of: #"url\((https://[^)]+\.ttf)\)"#, options: .regularExpression) else { return nil }
        let match = css[range].dropFirst(4).dropLast()
        return URL(string: String(match))
    }

    /// « Helvetica Neue », « helvetica-neue » et « HelveticaNeue » désignent
    /// la même famille.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }
}

// MARK: - Styles

enum Style {
    /// « SemiBold Italic » → (600, true). L'ordre des essais compte :
    /// « extrabold » contient « bold », « semibold » aussi.
    static func parse(_ style: String) -> (weight: Int, italic: Bool) {
        let s = Library.key(style)
        let italic = s.contains("italic") || s.contains("oblique")
        let table: [(String, Int)] = [
            ("hairline", 100), ("thin", 100), ("extralight", 200), ("ultralight", 200),
            ("semibold", 600), ("demibold", 600), ("extrabold", 800), ("ultrabold", 800),
            ("light", 300), ("book", 400), ("regular", 400), ("roman", 400), ("normal", 400),
            ("medium", 500), ("demi", 600), ("bold", 700), ("heavy", 800), ("black", 900), ("fat", 900),
        ]
        let weight = table.first { s.contains($0.0) }?.1 ?? 400
        return (weight, italic)
    }

    /// Le trait de graisse de CoreText (-1…1) en graisse CSS (100…900).
    static func css(fromTrait trait: CGFloat) -> Int {
        let table: [(CGFloat, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400),
                                       (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900)]
        return table.min { abs($0.0 - trait) < abs($1.0 - trait) }!.1
    }
}

// MARK: - Catalogues

/// Les listes de familles de Google Fonts et Fontshare, gardées sur le disque
/// une semaine : elles disent quelles graisses existent avant de rien
/// télécharger, et reconnaissent une police libre à son nom.
enum Catalog {

    struct GoogleEntry: Codable {
        let family: String
        let category: String
        let variants: [String]
        /// Rang de popularité chez Google : 1 pour la plus employée.
        let popularity: Int
        /// Vrai pour une famille faite pour l'alphabet latin.
        let latin: Bool
    }
    struct FontshareStyle: Codable { let weight: Int; let italic: Bool; let file: String }
    struct FontshareEntry: Codable {
        let family: String
        let category: String
        let styles: [FontshareStyle]
        /// Le fichier variable (graisse), s'il existe.
        let variable: String?
    }

    nonisolated(unsafe) private static var googleMemo: [String: GoogleEntry]?
    nonisolated(unsafe) private static var fontshareMemo: [String: FontshareEntry]?
    private static let lock = NSLock()

    static func google() -> [String: GoogleEntry] {
        lock.lock(); defer { lock.unlock() }
        if let googleMemo { return googleMemo }
        let entries: [GoogleEntry] = cached("google-v2.json") {
            guard var text = Network.text("https://fonts.google.com/metadata/fonts") else { return nil }
            // La réponse commence par une garde anti-JSONP : « )]}' ».
            if let start = text.firstIndex(of: "{") { text = String(text[start...]) }
            guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let list = root["familyMetadataList"] as? [[String: Any]]
            else { return nil }
            return list.compactMap { item in
                guard let family = item["family"] as? String,
                      let fonts = item["fonts"] as? [String: Any] else { return nil }
                let script = item["primaryScript"] as? String ?? ""
                return GoogleEntry(family: family, category: item["category"] as? String ?? "",
                                   variants: Array(fonts.keys),
                                   popularity: item["popularity"] as? Int ?? 99_999,
                                   latin: (script.isEmpty || script == "Latn") && item["isNoto"] as? Bool != true)
            }
        }
        let map = Dictionary(entries.map { (Library.key($0.family), $0) }, uniquingKeysWith: { a, _ in a })
        googleMemo = map
        return map
    }

    static func fontshare() -> [String: FontshareEntry] {
        lock.lock(); defer { lock.unlock() }
        if let fontshareMemo { return fontshareMemo }
        let entries: [FontshareEntry] = cached("fontshare-v2.json") {
            guard let text = Network.text("https://api.fontshare.com/v2/fonts?limit=100"),
                  let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let list = root["fonts"] as? [[String: Any]]
            else { return nil }
            return list.compactMap { item in
                guard let family = item["name"] as? String,
                      let styles = item["styles"] as? [[String: Any]] else { return nil }
                let parsed = styles.compactMap { style -> FontshareStyle? in
                    guard style["is_variable"] as? Bool != true,
                          let file = style["file"] as? String,
                          let weight = (style["weight"] as? [String: Any])?["weight"] as? Int
                    else { return nil }
                    return FontshareStyle(weight: weight, italic: style["is_italic"] as? Bool ?? false, file: file)
                }
                let variable = styles.first { $0["is_variable"] as? Bool == true && $0["is_italic"] as? Bool != true }?["file"] as? String
                return FontshareEntry(family: family, category: item["category"] as? String ?? "", styles: parsed,
                                      variable: variable)
            }
        }
        let map = Dictionary(entries.map { (Library.key($0.family), $0) }, uniquingKeysWith: { a, _ in a })
        fontshareMemo = map
        return map
    }

    /// Le fichier s'il a moins d'une semaine ; sinon le réseau ; sinon le
    /// vieux fichier quand même — une liste ancienne vaut mieux que rien.
    private static func cached<T: Codable>(_ name: String, fetch: () -> [T]?) -> [T] {
        let file = Library.folder.appending(path: name)
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date().timeIntervalSince($0) } ?? .infinity
        let stored = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([T].self, from: $0) }
        if let stored, age < 7 * 86_400 { return stored }
        if let fresh = fetch(), !fresh.isEmpty {
            if let data = try? JSONEncoder().encode(fresh) { try? data.write(to: file, options: .atomic) }
            return fresh
        }
        return stored ?? []
    }
}

// MARK: - Réseau

/// Des requêtes synchrones, courtes et bornées : on est déjà hors du fil
/// principal, et une police qui ne vient pas en quinze secondes ne viendra pas.
enum Network {
    static func text(_ address: String, agent: String? = nil) -> String? {
        guard let url = URL(string: address), let data = fetch(url, agent: agent) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func download(_ url: URL, to file: URL) -> Bool {
        guard let data = fetch(url, agent: nil), data.count > 1000 else { return false }
        return (try? data.write(to: file, options: .atomic)) != nil
    }

    private static func fetch(_ url: URL, agent: String?) -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        if let agent { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { box.data = data }
            done.signal()
        }.resume()
        done.wait()
        return box.data
    }

    private final class Box: @unchecked Sendable { var data: Data? }
}
