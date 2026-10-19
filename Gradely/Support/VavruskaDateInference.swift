import Foundation

/// Event pages write dates without a year ("v neděli 18. října", "Prodej
/// vstupenek začíná 12. 10. v 18.00"); this picks the year that makes sense.
enum VavruskaDateInference {
    static let prague = TimeZone(identifier: "Europe/Prague") ?? .current

    static var pragueCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prague
        return calendar
    }

    /// A Prague wall-clock date, or nil for impossible dates like 31. 2.
    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date? {
        let calendar = pragueCalendar
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) else {
            return nil
        }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    /// Prefers the year of a matching prodloužená/ples from the lesson plan,
    /// then the earliest year that is not more than 120 days in the past.
    static func eventStart(
        day: Int, month: Int, hour: Int, minute: Int,
        now: Date, anchors: [VavruskaEvent]
    ) -> Date? {
        let calendar = pragueCalendar
        for anchor in anchors where anchor.kind.isEvent {
            let parts = calendar.dateComponents([.year, .month, .day], from: anchor.start)
            if parts.month == month, parts.day == day, let year = parts.year {
                return date(year: year, month: month, day: day, hour: hour, minute: minute)
            }
        }

        let year = calendar.component(.year, from: now)
        let earliest = now.addingTimeInterval(-120 * 24 * 60 * 60)
        for candidate in [year - 1, year, year + 1] {
            if let date = date(year: candidate, month: month, day: day, hour: hour, minute: minute), date >= earliest {
                return date
            }
        }
        return nil
    }

    /// Sales open before the event, so a sale "after" the event belongs to the previous year.
    static func saleStart(
        day: Int, month: Int, year explicitYear: Int?, hour: Int, minute: Int,
        eventStart: Date
    ) -> Date? {
        if let explicitYear {
            return date(year: explicitYear, month: month, day: day, hour: hour, minute: minute)
        }
        let eventYear = pragueCalendar.component(.year, from: eventStart)
        guard var sale = date(year: eventYear, month: month, day: day, hour: hour, minute: minute) else { return nil }
        if sale > eventStart, let previous = date(year: eventYear - 1, month: month, day: day, hour: hour, minute: minute) {
            sale = previous
        }
        guard eventStart.timeIntervalSince(sale) < 330 * 24 * 60 * 60 else { return nil }
        return sale
    }

    /// Stable id for an event start, "20261018-1600" in Prague time.
    static func eventKey(_ date: Date) -> String {
        let parts = pragueCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d%02d%02d-%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }
}
