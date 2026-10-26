import SwiftUI

/// Brand colors from the app icon: charcoal cap, German flag red and gold.
/// Surfaces stay on system backgrounds so Light and Dark Mode feel native.
enum AppTheme {
    /// Flag gold. Progress, tint, and primary highlights.
    static let accent = Color(red: 0.89, green: 0.72, blue: 0.0)

    /// Cap / top flag stripe. Launch dark and strong type accents.
    static let ink = Color(red: 0.102, green: 0.102, blue: 0.141)

    /// Middle flag stripe. Use sparingly for alerts and emphasis.
    static let flagRed = Color(red: 0.89, green: 0.0, blue: 0.06)

    static let der = Color(red: 0.22, green: 0.40, blue: 0.62)
    static let die = Color(red: 0.62, green: 0.28, blue: 0.36)
    static let das = Color(red: 0.22, green: 0.48, blue: 0.38)

    static func genderColor(for gender: String?) -> Color {
        switch gender?.lowercased() {
        case "der", "m", "masculine": return der
        case "die", "f", "feminine": return die
        case "das", "n", "neuter": return das
        default: return .secondary
        }
    }
}
