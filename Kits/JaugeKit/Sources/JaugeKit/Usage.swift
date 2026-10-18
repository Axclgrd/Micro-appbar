import Foundation

/// Ce que Claude Code sait de l'abonnement, à la dernière réponse.
///
/// Les chiffres ne sont pas calculés ici : Claude Code les reçoit de
/// l'API à chaque réponse et les passe à sa ligne d'état (`rate_limits`).
/// Ce sont donc les vrais pourcentages du compte, pas une estimation à
/// partir de tokens comptés — et ils ne bougent que quand Claude Code sert.
public struct Usage: Codable, Sendable, Equatable {

    public struct Window: Codable, Sendable, Equatable {
        /// De 0 à 100.
        public var used: Double
        public var resetsAt: Date

        /// La fenêtre est passée : elle est repartie de zéro, même si aucune
        /// réponse ne l'a encore confirmé.
        public func isExpired(at now: Date = .now) -> Bool { resetsAt <= now }

        public func current(at now: Date = .now) -> Double { isExpired(at: now) ? 0 : used }
    }

    /// Un relevé, pour estimer le rythme de la session.
    public struct Sample: Codable, Sendable, Equatable {
        public var date: Date
        public var used: Double
        public var resetsAt: Date
    }

    /// La session de cinq heures.
    public var session: Window?
    /// La semaine.
    public var week: Window?
    public var updated: Date
    public var samples: [Sample] = []

    /// Où Claude Code dépose les relevés, et où Jauge les lit.
    public static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Micro-app/Jauge/usage.json")
    }

    public static func load() -> Usage? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Usage.self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // Atomique : Jauge lit pendant que Claude Code écrit.
        try? data.write(to: Self.file, options: .atomic)
    }

    // MARK: Rythme

    /// Assez de relevés récents pour parler de rythme : plus de trois
    /// minutes d'écart dans la session en cours.
    public func knowsPace(at now: Date = .now) -> Bool {
        guard let session else { return false }
        let recent = samples.filter { $0.resetsAt == session.resetsAt && now.timeIntervalSince($0.date) < 45 * 60 }
        guard let first = recent.first, let last = recent.last else { return false }
        return last.date.timeIntervalSince(first.date) > 3 * 60
    }

    /// Quand la session sera pleine au rythme des 45 dernières minutes ;
    /// `nil` si elle tiendra jusqu'à sa remise à zéro, ou si on ne sait pas.
    public func sessionFull(at now: Date = .now) -> Date? {
        guard let session, !session.isExpired(at: now) else { return nil }
        let recent = samples.filter {
            $0.resetsAt == session.resetsAt && now.timeIntervalSince($0.date) < 45 * 60
        }
        guard let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) > 3 * 60, last.used > first.used
        else { return nil }
        let perSecond = (last.used - first.used) / last.date.timeIntervalSince(first.date)
        let full = last.date.addingTimeInterval((100 - last.used) / perSecond)
        return full < session.resetsAt ? full : nil
    }
}

// MARK: - Ligne d'état

/// Appelé par Claude Code à chaque rafraîchissement de sa ligne d'état
/// (`Jauge --statusline`) : lit le JSON sur l'entrée standard, garde le
/// relevé, et rend la ligne à afficher.
///
/// Doit rester rapide et ne jamais échouer bruyamment : une erreur ici
/// s'afficherait sous chaque message de Claude Code.
public enum StatusLine {

    public static func run() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let root = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        let model = (root["model"] as? [String: Any])?["display_name"] as? String

        let limits = root["rate_limits"] as? [String: Any]
        let session = window(limits?["five_hour"])
        let week = window(limits?["seven_day"])

        if session != nil || week != nil {
            record(session: session, week: week)
        }
        print(line(session: session, week: week, model: model))
    }

    private static func window(_ value: Any?) -> Usage.Window? {
        guard let item = value as? [String: Any],
              let used = (item["used_percentage"] as? NSNumber)?.doubleValue,
              let resets = (item["resets_at"] as? NSNumber)?.doubleValue
        else { return nil }
        return Usage.Window(used: used, resetsAt: Date(timeIntervalSince1970: resets))
    }

    static func record(session: Usage.Window?, week: Usage.Window?) {
        let now = Date()
        var usage = Usage.load() ?? Usage(updated: now)
        usage.session = session ?? usage.session
        usage.week = week ?? usage.week
        usage.updated = now
        if let session {
            // Un relevé par minute suffit pour un rythme, et garde le fichier
            // petit : la ligne d'état se rafraîchit bien plus souvent.
            let last = usage.samples.last
            if last == nil || now.timeIntervalSince(last!.date) > 60 || last!.resetsAt != session.resetsAt {
                usage.samples.append(Usage.Sample(date: now, used: session.used, resetsAt: session.resetsAt))
            }
            usage.samples.removeAll { now.timeIntervalSince($0.date) > 6 * 3600 }
        }
        usage.save()
    }

    /// « Session 42 % · semaine 61 % · Opus 5.5 »
    static func line(session: Usage.Window?, week: Usage.Window?, model: String?) -> String {
        var parts: [String] = []
        if let session { parts.append("Session \(Int(session.used.rounded())) %") }
        if let week { parts.append("semaine \(Int(week.used.rounded())) %") }
        if let model { parts.append(model) }
        return parts.isEmpty ? "Jauge : en attente d'une réponse" : parts.joined(separator: " · ")
    }
}

// MARK: - Branchement

/// La ligne `statusLine` de `~/.claude/settings.json`, qui fait appeler
/// Jauge par Claude Code.
///
/// Jamais d'écrasement : si une autre ligne d'état est déjà réglée, Jauge le
/// dit et n'y touche pas. Et une copie du fichier est gardée avant toute
/// écriture.
public enum Hookup {

    public enum State: Equatable {
        case connected
        case absent
        /// Une autre ligne d'état est réglée : la commande en place.
        case occupied(String)
    }

    static var settings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
    }

    /// La commande que Claude Code doit lancer.
    public static func command(executable: String) -> String {
        "\"\(executable)\" --statusline"
    }

    public static func state() -> State {
        guard let current = statusCommand() else { return .absent }
        return current.contains("--statusline") && current.contains("Jauge") ? .connected : .occupied(current)
    }

    private static func statusCommand() -> String? {
        guard let data = try? Data(contentsOf: settings),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let line = root["statusLine"] as? [String: Any]
        else { return nil }
        return line["command"] as? String ?? ""
    }

    /// Ajoute la ligne d'état. Rend le nouvel état.
    @discardableResult
    public static func install(executable: String) -> State {
        let current = state()
        if case .occupied = current { return current }

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settings) {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // Un fichier illisible ne se réécrit pas : on perdrait ses réglages.
                return current
            }
            root = parsed
            try? data.write(to: settings.deletingLastPathComponent().appending(path: "settings.json.avant-jauge"))
        }
        root["statusLine"] = ["type": "command", "command": command(executable: executable), "padding": 0]
        guard let output = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        else { return current }
        try? FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? output.write(to: settings, options: .atomic)
        return state()
    }
}
