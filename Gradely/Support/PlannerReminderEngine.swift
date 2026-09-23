import Foundation

struct PlannerReminder: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let eventIDs: [UUID]
    let fireDate: Date
    let expiresAt: Date
    let title: String
    let body: String
    let deepLink: URL
}

enum PlannerReminderEngine {
    static let identifierPrefix = "gradey.planner-reminder."
    static let horizonDays = 7

    static func make(events: [SchoolEvent], preferences: NotificationPreferences,
                     now: Date = Date(), calendar: Calendar = .current) -> [PlannerReminder] {
        let today = calendar.startOfDay(for: now)
        var reminders: [PlannerReminder] = []
        for offset in 1...horizonDays {
            guard let dueDay = calendar.date(byAdding: .day, value: offset, to: today),
                  let reminderDay = calendar.date(byAdding: .day, value: -1, to: dueDay),
                  let plannedFire = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: reminderDay),
                  plannedFire > now else { continue } // No catch-up burst after the day's reminder time.
            let eligible = events.filter { event in
                guard event.kind != .note, event.expiresAt > now else { return false }
                // Date-only items retain their authored local calendar day when the device travels.
                if !event.hasTime {
                    let saved = event.calendar.dateComponents([.year, .month, .day], from: event.date)
                    let requested = calendar.dateComponents([.year, .month, .day], from: dueDay)
                    return saved.year == requested.year && saved.month == requested.month && saved.day == requested.day
                }
                return calendar.isDate(event.date, inSameDayAs: dueDay)
            }.sorted {
                if $0.isAssessment != $1.isAssessment { return $0.isAssessment }
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard !eligible.isEmpty else { continue }
            let fireDate = preferences.nextQuietHoursEnd(after: plannedFire) ?? plannedFire
            // Quiet-hour deferral is never allowed to turn preparation into a past-due alert.
            let stillUpcoming = eligible.filter { event in
                let due = event.hasTime ? event.date : dueDay
                return fireDate < due
            }
            guard fireDate > now, !preferences.isWithinQuietHours(at: fireDate), !stillUpcoming.isEmpty else { continue }
            let dateKey = dayKey(fireDate, calendar: calendar)
            let reminder = PlannerReminder(
                id: identifierPrefix + dateKey, eventIDs: stillUpcoming.map(\.id), fireDate: fireDate,
                expiresAt: stillUpcoming.map(\.expiresAt).min() ?? dueDay,
                title: AppL10n.string("planner.reminder.title"), body: body(for: stillUpcoming, preferences: preferences),
                deepLink: URL(string: "gradey://planner?day=\(dayKey(dueDay, calendar: calendar))")!
            )
            // Overlapping quiet windows can map two preparation days onto one delivery day.
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                if reminder.fireDate < reminders[index].fireDate { reminders[index] = reminder }
            } else { reminders.append(reminder) }
        }
        return reminders.sorted { $0.fireDate < $1.fireDate }
    }

    private static func body(for events: [SchoolEvent], preferences: NotificationPreferences) -> String {
        switch preferences.lockScreenDetail {
        case .privateSummary:
            return AppL10n.string("planner.reminder.private")
        case .markAndSubject:
            let subjects = Array(Set(events.compactMap(\.subjectName))).sorted().prefix(2).joined(separator: ", ")
            let key = subjects.isEmpty ? "planner.reminder.count" : "planner.reminder.subjects"
            return String(format: AppL10n.string(String.LocalizationValue(key)), locale: AppLanguageOverride.locale,
                          arguments: [String(events.count), subjects])
        case .fullDetails:
            let titles = events.prefix(2).map(\.title).joined(separator: ", ")
            return String(format: AppL10n.string("planner.reminder.details"), locale: AppLanguageOverride.locale,
                          arguments: [String(events.count), titles])
        }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }
}
