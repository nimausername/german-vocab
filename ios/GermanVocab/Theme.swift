import SwiftUI

/// Visual tokens only. Layout belongs to system containers (List, Form, NavigationStack).
enum AppTheme {
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let inkSoft = Color(red: 0.22, green: 0.25, blue: 0.28)
    static let muted = Color(red: 0.45, green: 0.48, blue: 0.51)
    static let hairline = Color(red: 0.08, green: 0.10, blue: 0.12).opacity(0.10)

    static let wash = Color(red: 0.965, green: 0.970, blue: 0.975)
    static let mist = Color(red: 0.88, green: 0.92, blue: 0.91)

    static let accent = Color(red: 0.10, green: 0.32, blue: 0.29)
    static let danger = Color(red: 0.72, green: 0.22, blue: 0.20)
    static let warning = Color(red: 0.72, green: 0.42, blue: 0.12)
    static let positive = Color(red: 0.18, green: 0.48, blue: 0.36)

    static let der = Color(red: 0.22, green: 0.40, blue: 0.62)
    static let die = Color(red: 0.62, green: 0.28, blue: 0.36)
    static let das = Color(red: 0.22, green: 0.48, blue: 0.38)

    static let reveal = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let press = Animation.easeOut(duration: 0.18)
    static let progress = Animation.easeInOut(duration: 0.55)

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func lemma(_ size: CGFloat = 52) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    static func headline() -> Font {
        .system(size: 20, weight: .semibold, design: .default)
    }

    static func body() -> Font {
        .system(size: 17, weight: .regular, design: .default)
    }

    static func caption() -> Font {
        .system(size: 13, weight: .medium, design: .default)
    }

    static func micro() -> Font {
        .system(size: 11, weight: .semibold, design: .default)
    }

    static func genderColor(for gender: String?) -> Color {
        switch gender?.lowercased() {
        case "der", "m", "masculine": return der
        case "die", "f", "feminine": return die
        case "das", "n", "neuter": return das
        default: return muted
        }
    }
}
