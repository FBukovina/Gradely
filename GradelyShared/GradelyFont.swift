import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Space Grotesk is Gradey's only typeface: every label, title and number uses it.
/// The faces ship in `GradelyShared/Fonts` (licence: `SpaceGrotesk-OFL.txt`).
enum GradelyFont {
    static let family = "Space Grotesk"

    private static let faces = ["SpaceGrotesk-Regular", "SpaceGrotesk-Medium", "SpaceGrotesk-Bold"]

    /// Registers the bundled faces for this process. Call once at launch in every
    /// target (app or extension); repeated calls are harmless.
    static func registerIfNeeded(in bundle: Bundle = .main) {
        for face in faces {
            guard let url = bundle.url(forResource: face, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// The platform's default point size for a text style, before Dynamic Type.
    static func pointSize(for style: Font.TextStyle) -> CGFloat {
        #if canImport(UIKit)
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        return UIFont.preferredFont(forTextStyle: uiTextStyle(style), compatibleWith: traits).pointSize
        #elseif canImport(AppKit)
        return NSFont.preferredFont(forTextStyle: nsTextStyle(style)).pointSize
        #else
        return 17
        #endif
    }

    #if canImport(UIKit)
    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
    #elseif canImport(AppKit)
    private static func nsTextStyle(_ style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
    #endif

    #if os(iOS)
    /// UIKit chrome that SwiftUI fonts don't reach: navigation titles, tab bar
    /// labels and segmented controls.
    static func applyUIKitAppearance() {
        func face(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
        }
        let navigation = UINavigationBar.appearance()
        navigation.titleTextAttributes = [.font: face("SpaceGrotesk-Bold", 17, .headline)]
        navigation.largeTitleTextAttributes = [.font: face("SpaceGrotesk-Bold", 34, .largeTitle)]

        let tabTitle: [NSAttributedString.Key: Any] = [.font: face("SpaceGrotesk-Medium", 10, .caption2)]
        let tabs = UITabBarAppearance()
        for layout in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = tabTitle
            layout.selected.titleTextAttributes = tabTitle
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs

        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.font: face("SpaceGrotesk-Medium", 13, .footnote)], for: .normal)
        segmented.setTitleTextAttributes([.font: face("SpaceGrotesk-Bold", 13, .footnote)], for: .selected)
    }
    #endif
}

extension Font {
    /// Space Grotesk with the size and Dynamic Type scaling of a system text style.
    /// `.weight(_:)` and `.monospacedDigit()` chain on it like on a system font.
    static func gradely(_ style: Font.TextStyle) -> Font {
        let font = Font.custom(GradelyFont.family, size: GradelyFont.pointSize(for: style), relativeTo: style)
        return style == .headline ? font.weight(.semibold) : font
    }

    /// Space Grotesk at a fixed point size that still scales with Dynamic Type.
    static func gradely(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom(GradelyFont.family, size: size, relativeTo: style).weight(weight)
    }

    /// Large screen titles (onboarding, settings, sheets).
    static func gradelyDisplay(
        size: CGFloat = 38,
        relativeTo style: Font.TextStyle = .largeTitle
    ) -> Font {
        .gradely(size: size, weight: .bold, relativeTo: style)
    }
}
