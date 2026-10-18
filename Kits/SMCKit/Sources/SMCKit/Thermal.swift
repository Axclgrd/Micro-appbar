import Foundation

/// Lecture des capteurs de température, regroupés en valeurs qui ont un sens
/// pour un humain plutôt qu'en 212 clés brutes.
///
/// Attention : toutes les clés `T*` de type `flt ` ne sont pas des capteurs.
/// Sur M2 Pro, `Tf06` (99.3 °C) et `Tf16` (85.1 °C) sont rigoureusement
/// constants dans le temps — ce sont des consignes thermiques du firmware, pas
/// des mesures. Les afficher donnerait une fausse alerte permanente. On liste
/// donc explicitement les capteurs retenus au lieu de balayer le préfixe `T`.
public struct ThermalReading: Sendable {
    public let performanceCores: Double?
    public let performanceCoresPeak: Double?
    public let efficiencyCores: Double?
    public let gpu: Double?
    public let battery: Double?
    public let chassis: Double?

    /// La valeur qui pilote l'affichage principal et le verdict : le point le
    /// plus chaud du SoC, car c'est lui qui déclenche le throttling.
    public var hotspot: Double? {
        [performanceCoresPeak, efficiencyCores, gpu].compactMap { $0 }.max()
    }
}

/// Verdict lisible : « est-ce normal ou pas ».
public enum ThermalVerdict: Sendable {
    case cool       // < 60
    case normal     // 60 – 75
    case warm       // 75 – 90
    case hot        // 90 – 100
    case throttling // >= 100

    public init(hotspot: Double) {
        switch hotspot {
        case ..<60:   self = .cool
        case ..<75:   self = .normal
        case ..<90:   self = .warm
        case ..<100:  self = .hot
        default:      self = .throttling
        }
    }

    public var label: String {
        switch self {
        case .cool:       return "Frais"
        case .normal:     return "Normal"
        case .warm:       return "Tiède"
        case .hot:        return "Chaud"
        case .throttling: return "Throttling"
        }
    }

    /// Ce que ça veut dire concrètement, en une phrase.
    public var explanation: String {
        switch self {
        case .cool:
            return "Machine au repos, rien à signaler."
        case .normal:
            return "Température de fonctionnement habituelle."
        case .warm:
            return "Sous charge. Normal, mais le châssis va chauffer."
        case .hot:
            return "Proche de la limite. Monter les ventilos aiderait."
        case .throttling:
            return "Le SoC réduit ses fréquences pour se protéger."
        }
    }

    /// Nom de couleur SF Symbols / SwiftUI côté UI.
    public var severity: Int {
        switch self {
        case .cool: return 0
        case .normal: return 1
        case .warm: return 2
        case .hot: return 3
        case .throttling: return 4
        }
    }
}

public struct ThermalSensors {

    /// Clusters de cœurs performance (P) — MacBook Pro M1 Pro / M2 Pro.
    static let performanceCoreKeys = [
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L",
        "Tp0P", "Tp0T", "Tp0X", "Tp0b", "Tp0f", "Tp0j",
    ]
    /// Cœurs efficience (E).
    static let efficiencyCoreKeys = ["Te02", "Te06", "Te0A", "Te0E"]
    /// GPU. `Tg0f…Tg0r` : M2 Pro ; `Tg05`, `Tg0D` : M1 Pro (relevées sur
    /// MacBookPro18,3, elles varient bien avec la charge).
    static let gpuKeys = ["Tg0f", "Tg0j", "Tg0n", "Tg0r", "Tg05", "Tg0D"]
    /// Batterie.
    static let batteryKeys = ["TB1T", "TB2T"]
    /// Châssis / repose-poignets — le capteur qui correspond à ce que tu sens.
    static let chassisKeys = ["Ts0P", "Ts1P", "Ts0S"]

    /// Bornes de vraisemblance : au-delà, la clé n'est pas une mesure valide.
    private static let plausibleRange: ClosedRange<Float> = 5...115

    private let smc: SMC
    /// Sous-ensemble des clés réellement présentes, résolu une seule fois.
    private let available: [String: [String]]

    public init(smc: SMC) {
        self.smc = smc
        var resolved: [String: [String]] = [:]
        let groups: [(String, [String])] = [
            ("pcore", Self.performanceCoreKeys),
            ("ecore", Self.efficiencyCoreKeys),
            ("gpu", Self.gpuKeys),
            ("battery", Self.batteryKeys),
            ("chassis", Self.chassisKeys),
        ]
        for (name, keys) in groups {
            resolved[name] = keys.filter { smc.exists($0) }
        }
        self.available = resolved
    }

    private func values(_ group: String) -> [Double] {
        guard let keys = available[group] else { return [] }
        return keys.compactMap { key in
            guard let value = try? smc.readFloat(key),
                  Self.plausibleRange.contains(value) else { return nil }
            return Double(value)
        }
    }

    private func mean(_ group: String) -> Double? {
        let v = values(group)
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    public func read() -> ThermalReading {
        let pcore = values("pcore")
        return ThermalReading(
            performanceCores: pcore.isEmpty ? nil : pcore.reduce(0, +) / Double(pcore.count),
            performanceCoresPeak: pcore.max(),
            efficiencyCores: mean("ecore"),
            gpu: mean("gpu"),
            battery: mean("battery"),
            chassis: mean("chassis")
        )
    }
}
