import Commun
import Foundation

/// Lancement d'un utilitaire système.
///
/// Volontairement synchrone : les appels ne sont faits que depuis des acteurs
/// dédiés, jamais depuis le main actor.
enum Shell {

    struct Result: Sendable {
        let status: Int32
        let out: Data
        let err: String

        var text: String { String(decoding: out, as: UTF8.self) }
        var ok: Bool { status == 0 }
    }

    /// Boîte de transfert entre les fils de lecture et l'appelant. L'accès est
    /// sérialisé par le `DispatchGroup` : on n'écrit qu'avant `leave()`, on ne
    /// lit qu'après `wait()`.
    private final class Box: @unchecked Sendable {
        var data = Data()
    }

    static func run(_ tool: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(status: -1, out: Data(), err: "\(tool) introuvable")
        }

        // Les deux tuyaux sont vidés en parallèle. Lire l'un jusqu'au bout
        // pendant que l'autre se remplit finit en interblocage dès que le
        // tampon du noyau est plein — diskutil, lui, écrit dans les deux.
        let outBox = Box(), errBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.wait()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            out: outBox.data,
            err: String(decoding: errBox.data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static let diskutil = "/usr/sbin/diskutil"
    static let lsof = "/usr/sbin/lsof"
}
