import SwiftUI

/// A wrapper that pairs a Font with its HugeiconsStyle for reliable auto-detection
public struct HugeiconsFont {
    public let font: Font
    public let style: HugeiconsStyle
    public let size: CGFloat
    
    public init(font: Font, style: HugeiconsStyle, size: CGFloat) {
        self.font = font
        self.style = style
        self.size = size
    }
}

