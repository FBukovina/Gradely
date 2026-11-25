import Foundation

enum DemoClock {
    /// `<flag> 2026-11-12` moves demo builds (`-uiTestingMockAPI`) to that
    /// day, keeping the time of day. Without the flag it's the real clock.
    static func launchNow(flag: String, arguments: [String] = ProcessInfo.processInfo.arguments) -> () -> Date {
        guard arguments.contains("-uiTestingMockAPI"),
              let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1),
              let day = Homework.schoolDate(arguments[index + 1]) else { return Date.init }
        let offset = day.timeIntervalSince(Homework.schoolCalendar.startOfDay(for: Date()))
        return { Date().addingTimeInterval(offset) }
    }
}
