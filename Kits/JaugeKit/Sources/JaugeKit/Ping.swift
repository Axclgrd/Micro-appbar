import AppKit
import Foundation

/// Le relevé demandé, quand la ligne d'état se tait.
///
/// La ligne d'état ne sert que dans le terminal : l'extension VS Code et
/// l'app Claude consomment le même abonnement sans jamais l'appeler, et la
/// jauge restait figée pendant qu'on travaillait. Toute réponse de Claude
/// Code porte pourtant l'état des limites : on en demande une, la plus petite
/// possible — Haiku, aucun outil, aucun contexte, une réponse de deux mots.
/// Mesuré : 0,0002 $ l'appel, deux cents fois moins qu'une analyse Fonte.
enum Ping {

    /// Bloquant : à appeler hors du fil principal. Vrai si un relevé est
    /// arrivé.
    static func run() -> Bool {
        guard let claude = locate() else { return false }
        let work = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "jauge-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: work) }
        let message = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"ok"}]}}"# + "\n"
        guard (try? message.write(to: work, atomically: true, encoding: .utf8)) != nil,
              let input = FileHandle(forReadingAtPath: work.path)
        else { return false }

        let process = Process()
        process.executableURL = claude
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        process.arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--safe-mode", "--tools", "", "--no-session-persistence",
            "--model", "claude-haiku-5-5", "--effort", "low",
            "--system-prompt", "Reponds seulement : ok",
        ]
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            .joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        // L'événement des limites, même si la réponse elle-même a échoué :
        // une session pleine refuse de répondre mais dit encore où elle en est.
        for line in data.split(separator: 0x0A).reversed() {
            guard let root = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  root["type"] as? String == "rate_limit_event",
                  let windows = (root["rate_limit_info"] as? [String: Any])?["unifiedWindows"] as? [String: Any]
            else { continue }
            let session = window(windows["five_hour"]), week = window(windows["seven_day"])
            guard session != nil || week != nil else { continue }
            StatusLine.record(session: session, week: week)
            return true
        }
        return false
    }

    /// `utilization` est une fraction, de 0 à 1.
    private static func window(_ value: Any?) -> Usage.Window? {
        guard let item = value as? [String: Any],
              let utilization = (item["utilization"] as? NSNumber)?.doubleValue,
              let resets = (item["resetsAt"] as? NSNumber)?.doubleValue
        else { return nil }
        return Usage.Window(used: utilization * 100, resetsAt: Date(timeIntervalSince1970: resets))
    }

    /// Une app lancée depuis le Finder n'hérite pas du PATH du shell.
    static func locate() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Claude sert-il en ce moment ? Claude Code (terminal ou extension) ou
    /// l'app Claude. Sinon, rien ne consomme, et rien ne vaut un relevé.
    static func claudeIsActive() -> Bool {
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.anthropic.claudefordesktop" }) {
            return true
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-q", "-x", "claude"]
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
