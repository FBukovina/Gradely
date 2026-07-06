import Foundation

struct TimetableTodaySummary: Equatable {
    enum State: Equatable {
        case empty
        case beforeSchool
        case current
        case betweenLessons
        case afterSchool
    }

    let state: State
    let currentLesson: ScheduledLesson?
    let nextLesson: ScheduledLesson?
    let changedLessons: [ScheduledLesson]
    let minutesRemainingInCurrent: Int?
    let minutesUntilNext: Int?

    var hasChanges: Bool {
        !changedLessons.isEmpty
    }
}

enum TimetableTodaySummaryBuilder {
    static func make(
        for day: ScheduledDay?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimetableTodaySummary? {
        guard let day, day.isToday else { return nil }

        let changedLessons = day.lessons.filter { $0.changeKind != .none }
        let timedLessons = day.lessons.compactMap { lesson -> TimedLesson? in
            guard let interval = timeInterval(for: lesson, on: day.date ?? now, calendar: calendar) else { return nil }
            return TimedLesson(lesson: lesson, start: interval.start, end: interval.end)
        }
        .sorted { $0.start < $1.start }

        let activeLessons = timedLessons.filter { !$0.lesson.isCanceled }
        guard !activeLessons.isEmpty else {
            return TimetableTodaySummary(
                state: day.lessons.isEmpty ? .empty : .afterSchool,
                currentLesson: nil,
                nextLesson: nil,
                changedLessons: changedLessons,
                minutesRemainingInCurrent: nil,
                minutesUntilNext: nil
            )
        }

        if let current = activeLessons.first(where: { $0.start <= now && now <= $0.end }) {
            let next = activeLessons.first(where: { $0.start > current.end })?.lesson
            return TimetableTodaySummary(
                state: .current,
                currentLesson: current.lesson,
                nextLesson: next,
                changedLessons: changedLessons,
                minutesRemainingInCurrent: positiveMinutes(from: now, to: current.end),
                minutesUntilNext: nil
            )
        }

        if let next = activeLessons.first(where: { $0.start > now }) {
            let first = activeLessons.first
            return TimetableTodaySummary(
                state: first?.lesson.id == next.lesson.id ? .beforeSchool : .betweenLessons,
                currentLesson: nil,
                nextLesson: next.lesson,
                changedLessons: changedLessons,
                minutesRemainingInCurrent: nil,
                minutesUntilNext: positiveMinutes(from: now, to: next.start)
            )
        }

        return TimetableTodaySummary(
            state: .afterSchool,
            currentLesson: nil,
            nextLesson: nil,
            changedLessons: changedLessons,
            minutesRemainingInCurrent: nil,
            minutesUntilNext: nil
        )
    }

    private static func timeInterval(
        for lesson: ScheduledLesson,
        on day: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        guard
            !lesson.hour.beginTime.isEmpty,
            !lesson.hour.endTime.isEmpty,
            let start = time(lesson.hour.beginTime, on: day, calendar: calendar),
            let end = time(lesson.hour.endTime, on: day, calendar: calendar)
        else {
            return nil
        }
        return (start, end)
    }

    private static func time(_ string: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = string.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private static func positiveMinutes(from start: Date, to end: Date) -> Int {
        max(0, Int(ceil(end.timeIntervalSince(start) / 60)))
    }

    private struct TimedLesson {
        let lesson: ScheduledLesson
        let start: Date
        let end: Date
    }
}
