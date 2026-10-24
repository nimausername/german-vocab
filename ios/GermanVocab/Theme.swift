import SwiftUI

/// Brand tint and article colors. Everything else uses system styles so the
/// interface follows Light and Dark Mode.
enum AppTheme {
    static let accent = Color(red: 0.10, green: 0.32, blue: 0.29)

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
