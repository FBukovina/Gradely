#if canImport(SwiftUI)
import SwiftUI

public extension GradelyWatchLessonChangeKind {
    /// Accent color for change chips and lesson emphasis, matching the iOS grade palette.
    var color: Color {
        switch self {
        case .none: .secondary
        case .canceled: Color(.sRGB, red: 0.847, green: 0.243, blue: 0.310)     // rose
        case .substitution: Color(.sRGB, red: 0.851, green: 0.561, blue: 0.063) // amber
        case .roomChanged: Color(.sRGB, red: 0.063, green: 0.541, blue: 0.580)  // teal
        case .added: Color(.sRGB, red: 0.686, green: 0.322, blue: 0.871)        // purple
        }
    }
}
#endif
