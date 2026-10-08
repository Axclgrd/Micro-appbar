import Foundation

public enum Format {
    /// Un âge lisible d'un coup d'œil : ce qui compte, c'est l'ordre de
    /// grandeur, pas la seconde près.
    public static func age(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        if value < 60 { return "à l'instant" }
        if value < 3600 { return "\(value / 60) min" }
        if value < 86_400 { return "\(value / 3600) h" }
        return "\(value / 86_400) j"
    }
}
