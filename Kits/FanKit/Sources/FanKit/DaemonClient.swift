import Commun
import Foundation
import Observation
import SMCKit

/// Dialogue avec `fancontrold`.
///
/// La connexion est **maintenue ouverte** tant que l'app vit : côté démon, le
/// mode manuel est adossé à la durée de vie du socket. C'est ce qui garantit
/// qu'une fermeture ou un plantage de l'app rend automatiquement la main à
/// macOS, sans avoir à faire confiance à un quelconque code de nettoyage.
actor DaemonConnection {

    enum Failure: Error, CustomStringConvertible {
        case notInstalled
        case refused
        case brokenPipe

        var description: String {
            switch self {
            case .notInstalled: return "Démon non installé"
            case .refused:      return "Connexion refusée"
            case .brokenPipe:   return "Connexion perdue"
            }
        }
    }

    private var fd: Int32 = -1
    private var inbox = Data()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isConnected: Bool { fd >= 0 }

    func connect() throws {
        guard fd < 0 else { return }
        guard FileManager.default.fileExists(atPath: FanProtocol.socketPath) else {
            throw Failure.notInstalled
        }

        let handle = socket(AF_UNIX, SOCK_STREAM, 0)
        guard handle >= 0 else { throw Failure.refused }

        var address = FanProtocol.address(for: FanProtocol.socketPath)
        let result = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(handle, sa, FanProtocol.addressLength)
            }
        }
        guard result == 0 else {
            close(handle)
            throw Failure.refused
        }
        fd = handle
    }

    func disconnect() {
        if fd >= 0 { close(fd) }
        fd = -1
        inbox.removeAll()
    }

    @discardableResult
    func send(_ request: FanRequest) throws -> FanReply {
        try connect()

        var payload = try encoder.encode(request)
        payload.append(0x0a)
        let written = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written > 0 else { disconnect(); throw Failure.brokenPipe }

        // Réponse délimitée par un retour à la ligne.
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            if let newline = inbox.firstIndex(of: 0x0a) {
                let line = inbox[inbox.startIndex..<newline]
                inbox = inbox[inbox.index(after: newline)...]
                return try decoder.decode(FanReply.self, from: Data(line))
            }
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { disconnect(); throw Failure.brokenPipe }
            inbox.append(contentsOf: chunk[0..<n])
        }
    }
}

/// État du contrôle manuel, exposé à l'interface.
@MainActor
@Observable
final class FanCommander {

    /// `true` quand le démon répond.
    private(set) var available = false
    private(set) var isManual = false
    private(set) var safetyOverride = false
    private(set) var status: String?

    /// Position du curseur, en RPM. Persistée entre deux ouvertures du panneau.
    var sliderRPM: Double = 3500
    private(set) var minimumRPM: Double = 2300
    private(set) var maximumRPM: Double = 6800

    private let connection = DaemonConnection()

    func probe() async {
        do {
            let reply = try await connection.send(FanRequest(command: .status))
            apply(reply)
            available = true
            status = nil
        } catch {
            available = false
            isManual = false
            status = "\(error)"
        }
    }

    func setManual(_ rpm: Double) async {
        do {
            let reply = try await connection.send(FanRequest(command: .manual, rpm: rpm))
            apply(reply)
            status = nil
        } catch {
            available = false
            status = "\(error)"
        }
    }

    func setAutomatic() async {
        do {
            let reply = try await connection.send(FanRequest(command: .auto))
            apply(reply)
            status = nil
        } catch {
            available = false
            status = "\(error)"
        }
    }

    private func apply(_ reply: FanReply) {
        minimumRPM = reply.minimumRPM
        maximumRPM = reply.maximumRPM
        safetyOverride = reply.safetyOverride
        isManual = reply.requestedRPM != nil
        if let requested = reply.requestedRPM {
            sliderRPM = requested
        } else {
            sliderRPM = sliderRPM.clamped(to: reply.minimumRPM...reply.maximumRPM)
        }
    }
}
