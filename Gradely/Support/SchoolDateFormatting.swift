import Foundation

enum SchoolDateFormatting {
    static func date(_ date: Date, locale: Locale = AppLanguageOverride.locale,
                     timeZone: TimeZone = .current, includeTime: Bool = false) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: includeTime ? .shortened : .omitted,
                                       locale: locale, timeZone: timeZone))
    }

    /// Day and month only ("31. 5."), with the year when it isn't the current one.
    /// Numeric, so it follows the device region (like the Absence day list)
    /// rather than the app language, whose English locale has no region. ICU's
    /// English-in-Czechia pattern drops the final dot ("31. 5"), so Czech and
    /// Slovak regions use the native pattern.
    static func shortDate(
        _ date: Date,
        timeZone: TimeZone = .current,
        region: Locale.Region? = Locale.current.region,
        now: Date = Date()
    ) -> String {
        let locale: Locale = switch region {
        case .czechia?: Locale(identifier: "cs_CZ")
        case .slovakia?: Locale(identifier: "sk_SK")
        default: .current
        }
        var style = Date.FormatStyle(locale: locale, timeZone: timeZone).day().month(.defaultDigits)
        if !Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }

    /// Weekday in the app's language plus the short date, e.g. "út 10. 2." or "Tue 10. 2.".
    static func weekdayShortDate(_ date: Date) -> String {
        let weekday = date.formatted(Date.FormatStyle(locale: AppLanguageOverride.locale).weekday(.abbreviated))
        return weekday + " " + shortDate(date)
    }

    static func eventDate(_ event: SchoolEvent, locale: Locale = AppLanguageOverride.locale,
                          deviceTimeZone: TimeZone = .current, includeTime: Bool = true) -> String {
        date(event.date, locale: locale, timeZone: event.hasTime ? deviceTimeZone : event.calendar.timeZone,
             includeTime: includeTime && event.hasTime)
    }
}
