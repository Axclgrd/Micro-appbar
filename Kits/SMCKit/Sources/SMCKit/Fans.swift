import Foundation

/// État d'un ventilateur à un instant donné.
public struct FanState: Sendable, Identifiable {
    public let index: Int
    public let actual: Double
    public let target: Double
    public let minimum: Double
    public let maximum: Double
    public let mode: FanMode

    public var id: Int { index }

    /// Position sur la plage min–max, dans [0, 1].
    public var load: Double {
        guard maximum > minimum else { return 0 }
        return ((actual - minimum) / (maximum - minimum)).clamped(to: 0...1)
    }
}

public enum FanMode: UInt8, Sendable {
    case automatic = 0
    case manual = 1
    /// Le démon thermique du système garde la main (M3 et suivants).
    case system = 3

    public var isManual: Bool { self == .manual }
}

/// Accès aux ventilateurs. La lecture est libre ; les méthodes d'écriture
/// exigent que le processus tourne en root — elles ne sont donc appelées que
/// depuis le démon privilégié, jamais depuis l'app menu bar.
public struct FanController {

    private let smc: SMC
    public let count: Int
    /// Casse de la clé de mode : majuscule (`F0Md`) jusqu'à M4, minuscule
    /// (`F0md`) sur M5. On sonde à l'exécution plutôt que de coder en dur.
    private let modeKeySuffix: String

    public init(smc: SMC) throws {
        self.smc = smc
        self.count = Int(try smc.readUInt8("FNum"))
        self.modeKeySuffix = smc.exists("F0Md") ? "Md" : "md"
    }

    private func modeKey(_ index: Int) -> String { "F\(index)\(modeKeySuffix)" }

    public func state(of index: Int) throws -> FanState {
        FanState(
            index: index,
            actual: Double(try smc.readFloat("F\(index)Ac")),
            target: Double(try smc.readFloat("F\(index)Tg")),
            minimum: Double(try smc.readFloat("F\(index)Mn")),
            maximum: Double(try smc.readFloat("F\(index)Mx")),
            mode: FanMode(rawValue: (try? smc.readUInt8(modeKey(index))) ?? 0) ?? .automatic
        )
    }

    public func allStates() -> [FanState] {
        (0..<count).compactMap { try? state(of: $0) }
    }

    // MARK: Écriture — root requis

    /// Impose une vitesse. La consigne est bornée à la plage constructeur :
    /// écrire hors plage n'accélère rien et peut être refusé par le firmware.
    public func setSpeed(_ rpm: Double, fan index: Int) throws {
        let bounds = try state(of: index)
        let clamped = rpm.clamped(to: bounds.minimum...bounds.maximum)
        try smc.writeUInt8(modeKey(index), FanMode.manual.rawValue)
        try smc.writeFloat("F\(index)Tg", Float(clamped))
    }

    public func setSpeedAll(_ rpm: Double) throws {
        for index in 0..<count { try setSpeed(rpm, fan: index) }
    }

    /// Rend la main à macOS. Idempotent, et volontairement tolérant :
    /// on tente chaque ventilateur même si le précédent échoue, parce que
    /// c'est le chemin de secours.
    @discardableResult
    public func restoreAutomatic() -> [Error] {
        var errors: [Error] = []
        for index in 0..<count {
            do { try smc.writeUInt8(modeKey(index), FanMode.automatic.rawValue) }
            catch { errors.append(error) }
        }
        return errors
    }

    /// Repasse en automatique **et confirme** que ça a pris.
    ///
    /// Le SMC applique les écritures de façon asynchrone : une relecture
    /// immédiate renvoie encore l'ancienne valeur. Vérifier sans attendre fait
    /// conclure à tort à un échec — et, sur le chemin de secours, pousserait à
    /// « réparer » un état qui était déjà bon. On réessaie donc avec un délai.
    @discardableResult
    public func restoreAutomaticVerified(attempts: Int = 4,
                                         settle: TimeInterval = 0.25) -> Bool {
        for _ in 0..<attempts {
            restoreAutomatic()
            Thread.sleep(forTimeInterval: settle)
            if isFullyAutomatic() { return true }
        }
        return isFullyAutomatic()
    }

    /// Vérifie que tous les ventilateurs sont bien repassés en automatique.
    public func isFullyAutomatic() -> Bool {
        (0..<count).allSatisfy { index in
            guard let mode = try? smc.readUInt8(modeKey(index)) else { return false }
            return mode != FanMode.manual.rawValue
        }
    }

    /// Plage exploitable, prise sur le ventilateur 0 (identique sur les deux).
    public func range() -> ClosedRange<Double> {
        guard let first = try? state(of: 0), first.maximum > first.minimum else {
            return 2000...6000
        }
        return first.minimum...first.maximum
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
