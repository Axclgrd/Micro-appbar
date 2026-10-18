import Commun
import SwiftUI

@MainActor
public final class JaugeModule: Module {
    private let jauge = Jauge.shared

    public init() {
        // Les alertes partent même panneau fermé : la surveillance commence
        // avec l'app, pas avec le panneau.
        jauge.start()
    }

    public let id = "jauge"
    public let title = "Jauge"

    /// L'aiguille suit la session.
    public var symbol: String {
        switch session ?? 0 {
        case ..<20: "gauge.with.dots.needle.0percent"
        case ..<45: "gauge.with.dots.needle.33percent"
        case ..<60: "gauge.with.dots.needle.50percent"
        case ..<85: "gauge.with.dots.needle.67percent"
        default: "gauge.with.dots.needle.100percent"
        }
    }

    /// Le pourcentage de la session, à côté de l'icône : la seule chose
    /// qu'on veut lire sans rien ouvrir.
    public var badge: String? {
        session.map { "\(Int($0.rounded())) %" }
    }

    public var summary: String {
        guard let usage = jauge.usage else { return "" }
        var parts: [String] = []
        if let session = usage.session { parts.append("session \(Int(session.current().rounded())) %") }
        if let week = usage.week { parts.append("semaine \(Int(week.current().rounded())) %") }
        return parts.joined(separator: " · ")
    }

    private var session: Double? {
        jauge.usage?.session?.current()
    }

    /// Ouvrir le panneau, c'est vouloir le chiffre du moment : un relevé
    /// part s'il a plus de deux minutes.
    public func activate() {
        jauge.refreshHookup()
        jauge.refreshIfStale(after: 2 * 60, onlyWhenActive: false)
    }

    public func makePanel() -> AnyView {
        AnyView(JaugePanel(jauge: jauge))
    }
}
