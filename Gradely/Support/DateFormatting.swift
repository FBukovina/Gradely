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
            Date.FormatStyle(locale: AppLanguageOverride.locale)
                .day()
                .month(.defaultDigits)
                .year()
        )
    }

    static func relativeDate(_ string: String, relativeTo now: Date = Date()) -> String {
        guard let date = date(from: string) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguageOverride.locale
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

/// Week math for the timetable: Monday-anchored navigation and the API `date` parameter.
enum TimetableDates {
    /// Gregorian calendar pinned to Monday-first so week boundaries match the Czech school week
    /// regardless of the device locale.
    static let weekCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    private static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Monday of the week containing `date`.
    static func monday(of date: Date) -> Date {
        let components = weekCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return weekCalendar.date(from: components) ?? date
    }

    /// Shifts `date` by whole weeks (negative goes back).
    static func addingWeeks(_ count: Int, to date: Date) -> Date {
        weekCalendar.date(byAdding: .weekOfYear, value: count, to: date) ?? date
    }

    /// `yyyy-MM-dd` string for the timetable `date` query parameter.
    static func apiDateString(_ date: Date) -> String {
        apiFormatter.string(from: date)
    }

    /// Localized Monday–Friday range label, e.g. "8 – 12 Jun" / "8.–12. čvn".
    static func weekRangeTitle(
        weekStart monday: Date,
        locale: Locale = AppLanguageOverride.locale
    ) -> String {
        let friday = weekCalendar.date(byAdding: .day, value: 4, to: monday) ?? monday
        let dayMonth = Date.FormatStyle(locale: locale).day().month(.abbreviated)
        guard monday < friday else {
            return monday.formatted(dayMonth)
        }
        return (monday..<friday).formatted(.interval.day().month(.abbreviated).locale(locale))
    }

    static func weekdayAbbreviation(
        _ date: Date,
        locale: Locale = AppLanguageOverride.locale
    ) -> String {
        date.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated))
    }

    static func dayNumber(
        _ date: Date,
        locale: Locale = AppLanguageOverride.locale
    ) -> String {
        date.formatted(Date.FormatStyle(locale: locale).day())
    }

    /// API `DayOfWeek` is 1 = Monday … 7 = Sunday; `shortWeekdaySymbols[0]` is Sunday.
    static func weekdayAbbreviation(
        dayOfWeek: Int,
        locale: Locale = AppLanguageOverride.locale
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.shortWeekdaySymbols
        let index = dayOfWeek % 7
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}
