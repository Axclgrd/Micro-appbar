import Foundation

/// Protocole entre l'app menu bar (non privilégiée) et `fancontrold` (root).
///
/// Transport : socket de domaine Unix, messages JSON délimités par des retours
/// à la ligne. Volontairement pas de XPC : `SMAppService`/`SMJobBless` exigent
/// une signature Developer ID payante, inutile pour un usage personnel.
public enum FanProtocol {
    public static let socketPath = "/var/run/fancontrold.sock"

    /// Construit un `sockaddr_un` pour le chemin donné.
    ///
    /// La capacité de `sun_path` est calculée *avant* d'en prendre un pointeur
    /// mutable : la lire depuis l'intérieur du bloc constituerait un accès
    /// chevauchant, que Swift refuse.
    public static func address(for path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                _ = strncpy(dst, path, capacity - 1)
            }
        }
        return addr
    }

    /// Longueur à passer à `bind`/`connect`.
    public static let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
}

public struct FanRequest: Codable, Sendable {
    public enum Command: String, Codable, Sendable {
        case status
        case manual
        case auto
    }

    public let command: Command
    /// Consigne en tours/minute, uniquement pour `.manual`.
    public let rpm: Double?

    public init(command: Command, rpm: Double? = nil) {
        self.command = command
        self.rpm = rpm
    }
}

public struct FanReply: Codable, Sendable {
    public struct Fan: Codable, Sendable {
        public let index: Int
        public let actual: Double
        public let target: Double
        public let manual: Bool

        public init(index: Int, actual: Double, target: Double, manual: Bool) {
            self.index = index
            self.actual = actual
            self.target = target
            self.manual = manual
        }
    }

    public let ok: Bool
    public let fans: [Fan]
    public let minimumRPM: Double
    public let maximumRPM: Double
    /// Consigne demandée par l'utilisateur, `nil` en mode automatique.
    public let requestedRPM: Double?
    /// `true` quand le démon a relevé la consigne de force pour cause de
    /// température excessive — l'interface doit le dire à l'utilisateur.
    public let safetyOverride: Bool
    public let message: String?

    public init(ok: Bool, fans: [Fan], minimumRPM: Double, maximumRPM: Double,
                requestedRPM: Double?, safetyOverride: Bool, message: String? = nil) {
        self.ok = ok
        self.fans = fans
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.requestedRPM = requestedRPM
        self.safetyOverride = safetyOverride
        self.message = message
    }
}
