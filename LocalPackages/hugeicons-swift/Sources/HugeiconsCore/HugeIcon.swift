import SwiftUI

public struct HugeIcon: View {
    private let glyph: String
    private let font: Font
    private let color: Color

    public init(codepoint: UInt32, font: Font, color: Color = .primary) {
        guard let scalar = UnicodeScalar(codepoint) else {
            self.glyph = ""
            self.font = font
            self.color = color
            return
        }
        self.glyph = String(scalar)
        self.font = font
        self.color = color
    }

    public init(scalar: UnicodeScalar, font: Font, color: Color = .primary) {
        self.glyph = String(scalar)
        self.font = font
        self.color = color
    }

    public var body: some View {
        Text(glyph)
            .font(font)
            .foregroundColor(color)
            .accessibilityHidden(true)
    }
}


