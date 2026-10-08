import Foundation

enum BandeFormat {
    /// Une durée de piste : ce qui compte, c'est de situer — dix secondes ou
    /// une heure — pas la précision.
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d h %02d", h, m) }
        if m > 0 { return String(format: "%d min %02d s", m, s) }
        return "\(s) s"
    }
}
