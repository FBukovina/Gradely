import Foundation

enum MarkDateFormatter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        if let date = isoFormatter.date(from: string) {
            return date
        }
        if let date = fallbackISOFormatter.date(from: string) {
            return date
        }
        return fallbackDate(from: string)
    }

    static func fullDate(_ string: String) -> String {
        guard let date = date(from: string) else {
            return String(string.split(separator: "T").first ?? "")
        }

        return date.formatted(
            .dateTime
                .day()
                .month(.defaultDigits)
                .year()
        )
    }

    static func relativeDate(_ string: String, relativeTo now: Date = Date()) -> String {
        guard let date = date(from: string) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func fallbackDate(from string: String) -> Date? {
        let value = String(string.split(separator: "T").first ?? "")
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
