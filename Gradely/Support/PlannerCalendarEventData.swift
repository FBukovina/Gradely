import Foundation

/// Pure event mapping; EventKit objects and authorization never enter the views or model.
struct PlannerCalendarEventData: Equatable {
    let title: String
    let notes: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String
    let url: URL

    static func make(from item: PlannerItem) throws -> PlannerCalendarEventData {
        let calendar = item.calendar
        let start: Date
        let end: Date
        let allDay: Bool
        let lessonDuration = item.lesson.flatMap { lesson -> TimeInterval? in
            guard let start = lesson.start, let end = lesson.end, end > start else { return nil }
            return end.timeIntervalSince(start)
        } ?? 30 * 60

        if let due = item.dueDate {
            allDay = !item.dueHasTime
            start = allDay ? calendar.startOfDay(for: due) : due
            end = allDay ? (calendar.date(byAdding: .day, value: 1, to: start) ?? start) : start.addingTimeInterval(lessonDuration)
        } else if let lessonStart = item.lesson?.start {
            allDay = false
            start = lessonStart
            end = start.addingTimeInterval(lessonDuration)
        } else if let date = item.linkedDate {
            allDay = true
            start = calendar.startOfDay(for: date)
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        } else {
            throw PlannerError.dateRequired
        }

        let context = item.subject.map {
            String(format: AppL10n.string("planner.calendar.subjectType"), $0.displayName, item.type.title)
        } ?? item.type.title
        var title = String(format: AppL10n.string("planner.calendar.title"), context, item.title)
        if item.isCompleted {
            title = String(format: AppL10n.string("planner.calendar.completedTitle"), title)
        }
        return PlannerCalendarEventData(
            title: title, notes: item.notes, start: start, end: end, isAllDay: allDay,
            timeZoneIdentifier: item.timeZoneIdentifier, url: item.calendarURL
        )
    }
}
