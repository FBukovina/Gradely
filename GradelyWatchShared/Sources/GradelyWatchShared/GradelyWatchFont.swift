#if os(watchOS)
import CoreText
import SwiftUI
import UIKit

/// Space Grotesk on Apple Watch. The faces ship in this package's `Fonts`
/// folder (licence: `SpaceGrotesk-OFL.txt`); the iPhone and Mac apps use
/// `GradelyFont` from `GradelyShared` instead.
public enum GradelyWatchFont {
    static let family = "Space Grotesk"

    private static let faces = ["SpaceGrotesk-Regular", "SpaceGrotesk-Medium", "SpaceGrotesk-Bold"]

    /// Registers the faces for this process. Call once at launch in the watch app
    /// and in the complications extension; repeated calls are harmless.
    public static func registerIfNeeded() {
        for face in faces {
            guard let url = Bundle.module.url(forResource: face, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func pointSize(for style: Font.TextStyle) -> CGFloat {
        let uiStyle: UIFont.TextStyle = switch style {
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
        return UIFont.preferredFont(forTextStyle: uiStyle).pointSize
    }
}

public extension Font {
    /// Space Grotesk at the watch's current size for a system text style.
    static func gradely(_ style: Font.TextStyle) -> Font {
        let font = Font.custom(GradelyWatchFont.family, fixedSize: GradelyWatchFont.pointSize(for: style))
        return style == .headline ? font.weight(.semibold) : font
    }

    /// Space Grotesk at a fixed point size.
    static func gradely(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(GradelyWatchFont.family, fixedSize: size).weight(weight)
    }
}
#endif
