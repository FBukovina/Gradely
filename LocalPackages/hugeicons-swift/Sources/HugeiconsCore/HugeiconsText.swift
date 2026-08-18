import SwiftUI
import Foundation

public struct HugeiconsText: View {
    private let value: String
    private let font: Font
    private let style: HugeiconsStyle?
    private let primaryColor: Color?
    private let secondaryColor: Color?
    private let allLigatures: Bool
    
    // Init with HugeiconsFont (auto-detection works perfectly)
    public init(
        _ value: String,
        font: HugeiconsFont,
        color: Color = .primary,
        allLigatures: Bool = true
    ) {
        self.value = value
        self.font = font.font
        self.style = font.style
        self.primaryColor = color
        self.secondaryColor = nil
        self.allLigatures = allLigatures
    }
    
    // Init with HugeiconsFont and custom layer colors
    public init(
        _ value: String,
        font: HugeiconsFont,
        primaryColor: Color? = nil,
        secondaryColor: Color? = nil,
        allLigatures: Bool = true
    ) {
        self.value = value
        self.font = font.font
        self.style = font.style
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.allLigatures = allLigatures
    }
    
    // Legacy init with Font (tries auto-detection but may not work reliably)
    public init(
        _ value: String,
        font: Font,
        color: Color = .primary,
        allLigatures: Bool = true
    ) {
        self.value = value
        self.font = font
        self.style = nil
        self.primaryColor = color
        self.secondaryColor = nil
        self.allLigatures = allLigatures
    }
    
    // Legacy init with explicit style
    public init(
        _ value: String,
        font: Font,
        style: HugeiconsStyle,
        primaryColor: Color? = nil,
        secondaryColor: Color? = nil,
        allLigatures: Bool = true
    ) {
        self.value = value
        self.font = font
        self.style = style
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.allLigatures = allLigatures
    }

    public var body: some View {
        let detectedStyle = style ?? HugeiconsStyle.detect(from: font)
        
        if detectedStyle.isLayered {
            ZStack {
                // Primary layer
                makeText(value: value, color: primaryColor ?? .primary)
                
                // Secondary layer with default opacity
                makeText(
                    value: "\(value)-secondary",
                    color: secondaryColor ?? (primaryColor ?? .primary).opacity(0.3)
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value)
        } else {
            makeText(value: value, color: primaryColor ?? .primary)
                .accessibilityHidden(true)
        }
    }
    
    @ViewBuilder
    private func makeText(value: String, color: Color) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            Text(makeAttributedString(value: value))
                .font(font)
                .foregroundColor(color)
        } else {
            Text(value)
                .font(font)
                .foregroundColor(color)
        }
    }
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    private func makeAttributedString(value: String) -> AttributedString {
        let ns = NSMutableAttributedString(string: value)
        ns.addAttributes([.ligature: allLigatures ? 2 : 1], range: NSRange(location: 0, length: ns.length))
        return AttributedString(ns)
    }
}


