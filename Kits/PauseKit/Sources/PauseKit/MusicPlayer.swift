import AppKit

/// Ce qu'on sait faire d'Apple Music, et rien d'autre.
@MainActor
protocol Lecteur: AnyObject {
    /// Met en pause si, et seulement si, la lecture est en cours. Renvoie
    /// l'identifiant du morceau mis en pause, ou nil si on n'a rien touché.
    func mettreEnPause() -> ResultatPause
    /// Reprend si Music est toujours en pause sur ce même morceau.
    func reprendre(morceau: String) -> Bool
}

enum ResultatPause: Equatable {
    case rien                  // Music fermée ou pas en lecture
    case pause(morceau: String)
    case refuse                // autorisation Automation refusée
}

/// Apple Music par AppleScript.
///
/// `NSAppleScript` plutôt que ScriptingBridge : une seule chaîne par geste,
/// aucune en-tête générée. Music n'est jamais lancée par nous : on regarde
/// d'abord si elle tourne (NSWorkspace, qui n'envoie aucun Apple Event), et
/// l'adresse par identifiant de bundle ne sert qu'ensuite.
@MainActor
final class LecteurMusic: Lecteur {
    static let bundleID = "com.apple.Music"

    private var enCours: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func mettreEnPause() -> ResultatPause {
        guard enCours else { return .rien }
        let script = """
        tell application id "\(Self.bundleID)"
            if player state is playing then
                set tid to ""
                try
                    set tid to (persistent ID of current track)
                end try
                pause
                return "pause|" & tid
            end if
            return "rien"
        end tell
        """
        switch Self.run(script) {
        case .success(let out):
            return out.hasPrefix("pause|") ? .pause(morceau: String(out.dropFirst(6))) : .rien
        case .failure(let code):
            return code == -1743 ? .refuse : .rien
        }
    }

    func reprendre(morceau: String) -> Bool {
        guard enCours else { return false }
        let script = """
        tell application id "\(Self.bundleID)"
            if player state is paused then
                set tid to ""
                try
                    set tid to (persistent ID of current track)
                end try
                if tid is "\(morceau)" then
                    play
                    return "ok"
                end if
            end if
            return "non"
        end tell
        """
        if case .success("ok") = Self.run(script) { return true }
        return false
    }

    /// Lit l'état sans rien modifier — pour le diagnostic et les tests.
    static func etat() -> String? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        else { return nil }
        if case .success(let s) = run("tell application id \"\(bundleID)\" to return (player state as string)") {
            return s
        }
        return nil
    }

    private enum Sortie { case success(String), failure(Int) }

    private static func run(_ source: String) -> Sortie {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(0) }
        let result = script.executeAndReturnError(&error)
        if let error {
            return .failure((error[NSAppleScript.errorNumber] as? Int) ?? 0)
        }
        return .success(result.stringValue ?? "")
    }
}
