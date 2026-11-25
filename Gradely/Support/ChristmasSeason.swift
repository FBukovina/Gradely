import Foundation

/// Gradey's Christmas look: red brand colours, the red app icon, snow and a
/// countdown on Today. It runs from 29 November to the end of 24 December,
/// every year, so a build can ship early and switch itself on and off.
enum ChristmasSeason {
    /// `-uiTestingSeasonNow 2026-12-10` (with `-uiTestingMockAPI`) moves the
    /// season clock to that day.
    static let launchArgument = "-uiTestingSeasonNow"
    /// Debug-panel override, so the look can be tried outside the season.
    static let overrideKey = "debug.christmasTheme"

    enum Override: String, CaseIterable {
        case auto, on, off
    }

    static let now: () -> Date = DemoClock.launchNow(flag: launchArgument)

    /// Whether the Christmas look is showing. `Brand` reads it on every
    /// access; `refresh()` keeps it current when the app comes back.
    private(set) static var isActive = currentValue()

    static var isDemoClockSet: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-uiTestingMockAPI") && arguments.contains(launchArgument)
    }

    /// 29 November through 24 December, both inclusive.
    static func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return false }
        return (month == 11 && day >= 29) || (month == 12 && day <= 24)
    }

    /// Calendar days left until Christmas Eve this year; 0 on the day itself.
    static func daysUntilChristmasEve(from date: Date, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: date)
        guard let eve = calendar.date(from: DateComponents(year: year, month: 12, day: 24)) else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: eve).day ?? 0
        return max(days, 0)
    }

    /// Recomputes `isActive`; true when it changed.
    @discardableResult
    static func refresh() -> Bool {
        let value = currentValue()
        guard value != isActive else { return false }
        isActive = value
        return true
    }

    private static func currentValue() -> Bool {
        let stored = UserDefaults.standard.string(forKey: overrideKey) ?? ""
        switch Override(rawValue: stored) ?? .auto {
        case .on: return true
        case .off: return false
        case .auto: return contains(now())
        }
    }
}
