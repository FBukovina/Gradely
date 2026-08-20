import SwiftUI

enum WatchBrand {
    static let primary = Color(.sRGB, red: 0.102, green: 1.000, blue: 0.745)
    static let secondary = Color(.sRGB, red: 0.122, green: 0.976, blue: 0.549)
    static let onAccent = Color(.sRGB, red: 0.016, green: 0.094, blue: 0.078)
    static let canceled = Color(.sRGB, red: 0.95, green: 0.28, blue: 0.32)

    static let gradient = LinearGradient(
        colors: [primary, secondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static var screenBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.04, green: 0.18, blue: 0.16),
                    Color(.sRGB, red: 0.03, green: 0.12, blue: 0.10),
                    Color(.sRGB, red: 0.02, green: 0.07, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [primary.opacity(0.28), .clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 90
            )
            RadialGradient(
                colors: [secondary.opacity(0.18), .clear],
                center: .bottomLeading,
                startRadius: 4,
                endRadius: 80
            )
        }
        .ignoresSafeArea()
    }
}

enum WatchLessonFormatting {
    static func time(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let minutes = seconds / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        if minutes < 1 {
            return "\(seconds)s"
        }
        return "\(minutes) min"
    }
}
