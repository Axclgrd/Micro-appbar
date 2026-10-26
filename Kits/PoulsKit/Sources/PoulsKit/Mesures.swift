import Foundation

// Les valeurs que l'outil publie. Toutes `Sendable` et sans référence : elles
// traversent l'acteur de sondage pour arriver intactes sur le fil principal.
//
// Une convention tient tout le fichier : **une charge est une part de la
// machine**, entre 0 et 1. Le Moniteur d'activité d'Apple, lui, compte en
// pourcentage d'un cœur — 400 % veut dire quatre cœurs saturés. C'est juste,
// mais illisible : personne ne sait de tête combien de cœurs a son Mac, donc
// personne ne sait si 400 % est beaucoup. Ici, 33 % veut dire « un tiers du
// Mac », et les parts s'additionnent.

/// Charge processeur sur l'intervalle écoulé, en part de la machine.
public struct CPULoad: Sendable, Equatable {
    public let user: Double
    public let system: Double
    /// Nombre de cœurs logiques — ce qui donne son sens au pourcentage.
    public let cores: Int

    public var total: Double { min(1, user + system) }
}

/// Pression mémoire, telle que le noyau la voit lui-même.
///
/// C'est `kern.memorystatus_vm_pressure_level` qui décide, pas un calcul à
/// nous : c'est la valeur sur laquelle macOS se fonde pour comprimer, évincer
/// et tuer. Un ratio « utilisée / totale » ne dit rien d'utile — un Mac en
/// bonne santé remplit toujours sa mémoire.
public enum Pression: Int, Sendable, Comparable {
    case normale = 1
    case elevee = 2
    case critique = 4

    public static func < (a: Pression, b: Pression) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .normale:  "Normale"
        case .elevee:   "Élevée"
        case .critique: "Critique"
        }
    }
}

public struct MemoryUsage: Sendable, Equatable {
    public let total: UInt64
    /// Mémoire des applications, hors fichiers mis en cache.
    public let app: UInt64
    /// Mémoire câblée : le noyau et les pilotes, impossible à évincer.
    public let wired: UInt64
    /// Ce que macOS a compressé sur place plutôt que d'écrire sur le disque.
    public let compressed: UInt64
    /// Fichiers gardés en mémoire — récupérable à la demande, donc pas « pris ».
    public let cached: UInt64
    public let swapUsed: UInt64
    public let pression: Pression

    /// Ce que le Moniteur d'activité appelle « mémoire utilisée ».
    public var used: UInt64 { app + wired + compressed }
    public var ratio: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct DiskUsage: Sendable, Equatable {
    public let name: String
    public let free: UInt64
    public let total: UInt64

    public var used: UInt64 { total > free ? total - free : 0 }
    public var ratio: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// Débit réseau instantané, en octets par seconde, toutes interfaces réelles
/// confondues (la boucle locale et les ponts virtuels sont écartés).
public struct NetworkRate: Sendable, Equatable {
    public let down: Double
    public let up: Double

    public static let zero = NetworkRate(down: 0, up: 0)
}

/// Un consommateur, vu comme l'utilisateur le voit : une application, pas la
/// douzaine de processus qu'elle lance.
public struct AppUsage: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// Chemin du bundle `.app`, quand il y en a un : c'est de là que vient l'icône.
    public let bundlePath: String?
    /// Part de la machine, 0…1.
    public let cpu: Double
    /// Empreinte physique — la colonne « Mémoire » du Moniteur d'activité.
    public let memory: UInt64
    /// Octets lus + écrits par seconde.
    public let disk: Double
    public let processes: Int
}

/// Ce que l'outil classe, et selon quoi.
public enum Critere: String, CaseIterable, Sendable {
    case cpu, memoire, disque

    public var label: String {
        switch self {
        case .cpu:     "Processeur"
        case .memoire: "Mémoire"
        case .disque:  "Disque"
        }
    }
}

/// L'état global, en cinq marches comme le verdict thermique de FanControl.
public enum EtatMachine: Sendable {
    case repos, fluide, charge, sature

    public var label: String {
        switch self {
        case .repos:  "Au repos"
        case .fluide: "Fluide"
        case .charge: "Chargé"
        case .sature: "Saturé"
        }
    }

    public var explanation: String {
        switch self {
        case .repos:  "Rien ne travaille, la machine attend."
        case .fluide: "Charge habituelle, tout répond."
        case .charge: "Ça travaille. Le Mac reste réactif mais chauffe."
        case .sature: "Le Mac n'a plus de marge : ça rame maintenant."
        }
    }

    public var symbol: String {
        switch self {
        case .repos:  "gauge.with.dots.needle.0percent"
        case .fluide: "gauge.with.dots.needle.33percent"
        case .charge: "gauge.with.dots.needle.67percent"
        case .sature: "gauge.with.dots.needle.100percent"
        }
    }

    public var severity: Int {
        switch self {
        case .repos:  0
        case .fluide: 1
        case .charge: 2
        case .sature: 3
        }
    }

    /// Le verdict tient compte des deux ressources qui font ramer un Mac : le
    /// processeur et la mémoire. La pression mémoire pèse plus lourd — un CPU
    /// à fond rend la machine chaude, une mémoire saturée la rend inutilisable.
    public init(cpu: Double, pression: Pression, swap: UInt64) {
        if pression == .critique || (pression == .elevee && swap > 4 << 30) {
            self = .sature
        } else if cpu >= 0.65 || pression == .elevee {
            self = .charge
        } else if cpu >= 0.12 {
            self = .fluide
        } else {
            self = .repos
        }
    }
}

/// Un instantané cohérent : toutes les valeurs lues dans le même tour.
public struct Snapshot: Sendable {
    public let cpu: CPULoad
    public let memory: MemoryUsage
    public let disk: DiskUsage?
    public let network: NetworkRate
    /// Vide tant que le second relevé n'a pas eu lieu : un débit se mesure
    /// entre deux lectures, jamais sur une seule.
    public let apps: [AppUsage]

    public var etat: EtatMachine {
        EtatMachine(cpu: cpu.total, pression: memory.pression, swap: memory.swapUsed)
    }
}

// MARK: - Mise en forme

enum Chiffre {
    /// Un pourcentage entier, sans décimale qui tremble.
    static func part(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))\u{00A0}%"
    }

    static func octets(_ value: UInt64) -> String {
        value.formatted(.byteCount(style: .memory))
    }

    static func disque(_ value: UInt64) -> String {
        value.formatted(.byteCount(style: .file))
    }

    /// Un débit : « 1,2 Mo/s ». En dessous de 1 ko/s, on écrit zéro plutôt
    /// qu'un chiffre qui s'agite pour rien.
    static func debit(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 1024 else { return "0 o/s" }
        return "\(UInt64(bytesPerSecond).formatted(.byteCount(style: .file)))/s"
    }
}
