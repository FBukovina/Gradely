import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

// MARK: - Cross-platform SwiftUI helpers

enum GradelyKeyboardType {
    case numberPad
    case numbersAndPunctuation
    case url
}

enum GradelyTextInputAutocapitalization {
    case never
    case words
}

enum GradelyNavigationTitleDisplayMode {
    case inline
    case large
}

extension Color {
    static var gradelyGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    static var gradelySecondaryGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }

    static var gradelyTertiaryGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(.tertiarySystemGroupedBackground)
        #endif
    }

    static var gradelyTertiaryFill: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.22)
        #else
        Color(.tertiarySystemFill)
        #endif
    }

    static var gradelySystemGray: Color {
        #if os(macOS)
        Color(nsColor: .secondaryLabelColor)
        #else
        Color(.systemGray)
        #endif
    }

    static var gradelySystemGray5: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(.systemGray5)
        #endif
    }

    static var gradelySystemOrange: Color {
        #if os(macOS)
        Color(nsColor: .systemOrange)
        #else
        Color(.systemOrange)
        #endif
    }

    static var gradelySystemPurple: Color {
        #if os(macOS)
        Color(nsColor: .systemPurple)
        #else
        Color(.systemPurple)
        #endif
    }
}

extension ToolbarItemPlacement {
    static var gradelyTopBarLeading: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    static var gradelyTopBarTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }
}

extension View {
    @ViewBuilder
    func gradelyKeyboardType(_ keyboardType: GradelyKeyboardType) -> some View {
        #if os(iOS)
        self.keyboardType(keyboardType.uiKeyboardType)
        #else
        self
        #endif
    }

    @ViewBuilder
    func gradelyTextInputAutocapitalization(_ capitalization: GradelyTextInputAutocapitalization) -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(capitalization.swiftUIValue)
        #else
        self
        #endif
    }

    @ViewBuilder
    func gradelyNavigationTitleDisplayMode(_ displayMode: GradelyNavigationTitleDisplayMode) -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(displayMode.swiftUIValue)
        #endif
    }

    /// Presents a `TabView` as a native source-list sidebar on macOS while leaving
    /// the standard tab bar in place on iOS.
    @ViewBuilder
    func gradelySidebarAdaptable() -> some View {
        #if os(macOS)
        self.tabViewStyle(.sidebarAdaptable)
        #else
        self
        #endif
    }

    /// iOS-style circular tinted chip for toolbar icon buttons; a plain, system-tinted
    /// template icon on macOS where chips look out of place in the window toolbar.
    @ViewBuilder
    func gradelyToolbarIconButton() -> some View {
        #if os(macOS)
        self.imageScale(.large)
        #else
        self
            .font(.footnote.weight(.bold))
            .foregroundStyle(Brand.primary)
            .frame(width: 30, height: 30)
            .background(Brand.primary.opacity(0.15), in: Circle())
        #endif
    }
}

#if os(iOS)
private extension GradelyKeyboardType {
    var uiKeyboardType: UIKeyboardType {
        switch self {
        case .numberPad: .numberPad
        case .numbersAndPunctuation: .numbersAndPunctuation
        case .url: .URL
        }
    }
}

private extension GradelyTextInputAutocapitalization {
    var swiftUIValue: TextInputAutocapitalization {
        switch self {
        case .never: .never
        case .words: .words
        }
    }
}
#endif

#if !os(macOS)
private extension GradelyNavigationTitleDisplayMode {
    var swiftUIValue: NavigationBarItem.TitleDisplayMode {
        switch self {
        case .inline: .inline
        case .large: .large
        }
    }
}
#endif

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

// MARK: - Absence risk styling

extension AbsenceRiskLevel {
    /// Accent color for risk bars and percentages, reusing the grade palette.
    var color: Color {
        switch self {
        case .overLimit, .high: GradeBand.poor.foregroundColor
        case .watch: .gradelySystemOrange
        case .safe: Brand.primary
        case .unavailable: .secondary
        }
    }
}

// MARK: - Lesson change styling

extension LessonChangeKind {
    /// Accent color for the change chip and lesson emphasis, reusing the grade palette.
    var color: Color {
        switch self {
        case .none: .secondary
        case .canceled: GradeBand.poor.foregroundColor        // rose
        case .substitution: GradeBand.average.foregroundColor // amber
        case .roomChanged: GradeBand.good.foregroundColor     // teal
        case .added: .gradelySystemPurple                     // purple
        }
    }
}
