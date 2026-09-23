import Foundation

enum SchoolDateFormatting {
    static func date(_ date: Date, locale: Locale = AppLanguageOverride.locale,
                     timeZone: TimeZone = .current, includeTime: Bool = false) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: includeTime ? .shortened : .omitted,
                                       locale: locale, timeZone: timeZone))
    }

    static func eventDate(_ event: SchoolEvent, locale: Locale = AppLanguageOverride.locale,
                          deviceTimeZone: TimeZone = .current, includeTime: Bool = true) -> String {
        date(event.date, locale: locale, timeZone: event.hasTime ? deviceTimeZone : event.calendar.timeZone,
             includeTime: includeTime && event.hasTime)
    }
}
