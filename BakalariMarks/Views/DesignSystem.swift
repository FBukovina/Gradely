import SwiftUI

// MARK: - Brand palette

enum Brand {
    /// Teal brand primary (deep #17A185 light, bright #1AFFBE dark) — defined in the asset catalog.
    static let primary = Color("BrandPrimary")
    /// Emerald brand secondary (#1DA565 light, #1FF98C dark) — defined in the asset catalog.
    static let secondary = Color("BrandSecondary")

    /// Dark teal ink for text/icons placed on the bright teal gradient (à la Quipee).
    static let onAccent = Color(.sRGB, red: 0.016, green: 0.094, blue: 0.078)

    /// Diagonal teal→emerald gradient used for hero surfaces and the primary CTA.
    static let gradient = LinearGradient(
        colors: [primary, secondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Layered teal "aurora" glow used behind auth/hero content.
    static let auroraGlows: [Color] = [
        primary.opacity(0.30),
        secondary.opacity(0.22),
        primary.opacity(0.16),
    ]
}

// MARK: - Spacing & radius tokens

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let card: CGFloat = 20
    static let xl: CGFloat = 28
}

// MARK: - Grade band styling

extension GradeBand {
    /// Solid accent color used for numbers and emphasis.
    var foregroundColor: Color {
        switch self {
        case .excellent: Color(.sRGB, red: 0.118, green: 0.624, blue: 0.412) // emerald
        case .good: Color(.sRGB, red: 0.063, green: 0.541, blue: 0.580)       // teal
        case .average: Color(.sRGB, red: 0.851, green: 0.561, blue: 0.063)    // amber
        case .poor: Color(.sRGB, red: 0.847, green: 0.243, blue: 0.310)       // rose
        case .neutral: .secondary
        }
    }

    /// Soft tonal fill for badges and chips.
    var soft: Color {
        switch self {
        case .neutral: Color.gray.opacity(0.16)
        default: foregroundColor.opacity(0.14)
        }
    }

    /// Two-stop gradient used to tint hero surfaces by performance.
    var gradient: LinearGradient {
        let base = self == .neutral ? Brand.primary : foregroundColor
        return LinearGradient(
            colors: [base, base.opacity(0.78)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
