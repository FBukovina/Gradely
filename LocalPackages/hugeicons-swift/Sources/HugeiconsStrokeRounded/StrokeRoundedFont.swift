import SwiftUI
import HugeiconsCore

public enum HugeiconsStrokeRounded {
    private static let filename = "hgi-stroke-rounded.ttf"
    
    public static let style: HugeiconsStyle = .strokeRounded

    @discardableResult
    public static func load() -> String? {
        HugeiconsFontLoader.registerFontOnce(from: .module, fontFilename: filename, style: style)
    }

    public static func font(size: CGFloat) -> Font {
        HugeiconsFontLoader.font(from: .module, fontFilename: filename, size: size, style: style)
    }
    
    public static func hugeiconsFont(size: CGFloat) -> HugeiconsFont {
        HugeiconsFont(font: font(size: size), style: style, size: size)
    }
}


