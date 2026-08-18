import SwiftUI

public enum HugeiconsStyle {
    case bulkRounded
    case duotoneRounded
    case duotoneStandard
    case solidRounded
    case solidSharp
    case solidStandard
    case strokeRounded
    case strokeSharp
    case strokeStandard
    case twotoneRounded
    
    /// Returns true if this style uses two layers (primary + secondary)
    public var isLayered: Bool {
        switch self {
        case .bulkRounded, .duotoneRounded, .duotoneStandard, .twotoneRounded:
            return true
        default:
            return false
        }
    }
    
    /// Attempts to detect the style from a Font by looking up registered metadata
    /// Falls back to single-layer if detection fails
    public static func detect(from font: Font) -> HugeiconsStyle {
        let description = String(describing: font)
        
        if let nameRange = description.range(of: "name: \""),
           let endRange = description[nameRange.upperBound...].range(of: "\"") {
            let postScriptName = String(description[nameRange.upperBound..<endRange.lowerBound])
            if let style = HugeiconsFontLoader.getStyle(for: postScriptName) {
                return style
            }
        }
        
        let lower = description.lowercased()
        if lower.contains("bulk") && lower.contains("rounded") {
            return .bulkRounded
        } else if lower.contains("duotone") && lower.contains("rounded") {
            return .duotoneRounded
        } else if lower.contains("duotone") && lower.contains("standard") {
            return .duotoneStandard
        } else if lower.contains("twotone") && lower.contains("rounded") {
            return .twotoneRounded
        }
        
        return .solidRounded
    }
}
