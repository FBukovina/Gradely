import SwiftUI
import HugeiconsCore
import HugeiconsStrokeRounded
#if os(macOS)
import AppKit
import CoreText
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

    /// Brand-tinted toolbar icons with a consistent visual size on every platform.
    @ViewBuilder
    func gradelyToolbarIconButton() -> some View {
        #if os(macOS)
        self.imageScale(.large)
        #else
        self
            .font(.footnote.weight(.bold))
            .foregroundStyle(Brand.primary)
            .frame(width: 30, height: 30)
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

enum GradelyDisplayFont {
    static let fileName = "SpaceGrotesk-Bold"
    static let postScriptName = "SpaceGrotesk-Bold"

    /// iOS registers this face through `UIAppFonts`. macOS needs an explicit
    /// Core Text registration even when `ATSApplicationFontsPath` is set.
    static func registerIfNeeded(in bundle: Bundle = .main) {
        #if os(macOS)
        guard let url = bundle.url(forResource: fileName, withExtension: "ttf") else {
            return
        }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        #endif
    }
}

extension Font {
    /// Space Grotesk is Gradely's display face. Keep screen titles on one token
    /// so onboarding and standalone setup surfaces cannot drift apart.
    static func gradelyDisplay(
        size: CGFloat = 38,
        relativeTo textStyle: Font.TextStyle = .largeTitle
    ) -> Font {
        .custom(GradelyDisplayFont.postScriptName, size: size, relativeTo: textStyle)
    }
}

// MARK: - Iconography

/// Gradely's app-wide icon face. Like `Font.gradelyDisplay`, this is the single
/// design-system entry point for a bundled visual family—in this case
/// Hugeicons Stroke Rounded.
struct GradelyIcon: View {
    private let iconName: String
    private let size: CGFloat

    init(_ iconName: String, size: CGFloat = 18) {
        self.iconName = iconName
        self.size = size
    }

    /// Compatibility initializer for semantic icon names that previously came
    /// from SF Symbols. Rendering is always performed by Hugeicons.
    init(systemName: String, size: CGFloat = 18) {
        iconName = GradelyIconCatalog.hugeiconName(for: systemName)
        self.size = size
    }

    var body: some View {
        Text(attributedIconName)
        .font(HugeiconsStrokeRounded.font(size: size))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var attributedIconName: AttributedString {
        let value = NSMutableAttributedString(string: iconName)
        value.addAttribute(
            .ligature,
            value: 2,
            range: NSRange(location: 0, length: value.length)
        )
        return AttributedString(value)
    }
}

/// A native SwiftUI label whose icon is always rendered by Hugeicons.
struct GradelyLabel: View {
    private let title: Text
    private let iconName: String
    private let iconSize: CGFloat

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        iconSize: CGFloat = 16
    ) {
        self.title = Text(title)
        iconName = GradelyIconCatalog.hugeiconName(for: systemImage)
        self.iconSize = iconSize
    }

    init(
        _ title: String,
        systemImage: String,
        iconSize: CGFloat = 16
    ) {
        self.title = Text(LocalizedStringKey(title))
        iconName = GradelyIconCatalog.hugeiconName(for: systemImage)
        self.iconSize = iconSize
    }

    var body: some View {
        Label {
            title
        } icon: {
            GradelyIcon(iconName, size: iconSize)
        }
    }
}

/// Central migration map from the app's semantic icon vocabulary to Hugeicons.
/// Keeping it here prevents individual screens from drifting back to SF Symbols.
enum GradelyIconCatalog {
    static func hugeiconName(for semanticName: String) -> String {
        if let stepNumber = semanticName.first,
           semanticName.hasSuffix(".circle.fill"),
           stepNumber.isNumber {
            return "\(stepNumber)-circle"
        }

        let mapped = switch semanticName {
        case "apple.logo": "apple"
        case "arrow.clockwise": "refresh-04"
        case "arrow.down.right": "arrow-down-right-01"
        case "arrow.right", "arrow.right.circle", "arrow.right.circle.fill", "chevron.right":
            "arrow-right-01"
        case "arrow.up": "arrow-up-01"
        case "arrow.up.right": "arrow-up-right-01"
        case "bell.and.waves.left.and.right.fill", "bell.badge.fill":
            "notification-bubble"
        case "bell.fill": "notification-02"
        case "bubble.left.and.bubble.right.fill": "message-multiple-01"
        case "chart.bar.doc.horizontal": "analytics-01"
        case "clock": "clock-01"
        case "clock.arrow.circlepath": "reload"
        case "cloud.fill": "cloud"
        case "building.2.fill": "building-02"
        case "building.columns.fill": "university"
        case "calendar": "calendar-03"
        case "calendar.badge.checkmark": "calendar-check-in-02"
        case "calendar.badge.clock": "time-schedule"
        case "calendar.badge.exclamationmark": "calendar-remove-02"
        case "camera.fill": "camera-01"
        case "chart.line.uptrend.xyaxis": "chart-line-data-01"
        case "checklist": "check-list"
        case "checkmark": "tick-02"
        case "checkmark.circle.fill": "checkmark-circle-02"
        case "checkmark.seal.fill": "checkmark-badge-02"
        case "checkmark.shield.fill": "security-check"
        case "chevron.left": "arrow-left-01"
        case "chevron.up.chevron.down": "arrow-data-transfer-vertical"
        case "circle": "circle"
        case "clock.fill": "clock-01"
        case "creditcard.fill": "credit-card"
        case "door.left.hand.open": "door-open"
        case "ellipsis.circle": "more-horizontal-circle-01"
        case "envelope.fill": "mail-01"
        case "exclamationmark.circle.fill": "alert-circle"
        case "exclamationmark.triangle", "exclamationmark.triangle.fill": "alert-02"
        case "eye": "view"
        case "eye.slash": "view-off"
        case "fork.knife", "fork.knife.circle", "fork.knife.circle.fill": "restaurant-02"
        case "forward.fill": "forward-01"
        case "gearshape.fill": "settings-01"
        case "graduationcap.fill": "graduation-scroll"
        case "hand.raised.slash": "security-block"
        case "hand.tap": "touch-interaction-01"
        case "heart.circle.fill", "heart.fill": "favourite"
        case "info.circle", "info.circle.fill": "information-circle"
        case "key.fill": "key-01"
        case "link": "link-04"
        case "link.badge.plus": "link-circle-02"
        case "list.bullet.rectangle": "left-to-right-list-bullet"
        case "lock.shield.fill": "security-lock"
        case "magnifyingglass": "search-01"
        case "minus": "minus-sign"
        case "pause.circle.fill": "pause-circle"
        case "person.2.fill": "user-group"
        case "person.3.fill": "students"
        case "person.badge.key.fill": "user"
        case "person.crop.circle.badge.checkmark": "user-check-02"
        case "person.fill": "user"
        case "play.circle.fill": "play-circle"
        case "plus": "add-01"
        case "questionmark.circle": "help-circle"
        case "rectangle.portrait.and.arrow.right": "logout-01"
        case "sparkles": "sparkles"
        case "square.and.pencil": "edit-02"
        case "stop.fill": "stop"
        case "sun.max.fill": "sun-01"
        case "text.book.closed.fill": "book-02"
        case "trash": "delete-02"
        case "trash.slash": "delete-03"
        default: semanticName
        }

        // SF Symbol-style names that miss the map would otherwise be drawn as
        // raw text because Hugeicons only ligates its own kebab-case names.
        if mapped.contains(".") {
            return "help-circle"
        }
        return mapped
    }
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
