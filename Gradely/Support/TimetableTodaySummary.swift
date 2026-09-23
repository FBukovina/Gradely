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
        guard let day, day.date.map({ calendar.isDate($0, inSameDayAs: now) }) ?? day.isToday else { return nil }

        let timedLessons = day.lessons.compactMap { lesson -> TimedLesson? in
            guard let interval = timeInterval(for: lesson, on: day.date ?? now, calendar: calendar) else { return nil }
            return TimedLesson(lesson: lesson, start: interval.start, end: interval.end)
        }
        .sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            if $0.lesson.hour.id != $1.lesson.hour.id { return $0.lesson.hour.id < $1.lesson.hour.id }
            return $0.lesson.id < $1.lesson.id
        }

        // Today is an actionable view. Changes to ended or untimed lessons remain
        // in the full timetable, but should not compete with current/upcoming changes.
        let changedLessons = timedLessons
            .filter { $0.end > now && $0.lesson.changeKind != .none }
            .reduce(into: [TimedLesson]()) { changes, candidate in
                // Provider atoms have offset-based IDs, so repeated atoms can have
                // different IDs. Only collapse identical content in the same slot;
                // consecutive periods and different teaching groups stay separate.
                if !changes.contains(where: { sameChange($0, candidate) }) {
                    changes.append(candidate)
                }
            }
            .map(\.lesson)

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

        if let current = activeLessons.first(where: { $0.start <= now && now < $0.end }) {
            let next = activeLessons.first(where: { $0.start >= current.end })?.lesson
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
            let start = TimetableLessonTiming.date(lesson.hour.beginTime, on: day, calendar: calendar),
            let end = TimetableLessonTiming.date(lesson.hour.endTime, on: day, calendar: calendar),
            end > start
        else {
            return nil
        }
        return (start, end)
    }

    private static func positiveMinutes(from start: Date, to end: Date) -> Int {
        max(0, Int(ceil(end.timeIntervalSince(start) / 60)))
    }

    private static func sameChange(_ lhs: TimedLesson, _ rhs: TimedLesson) -> Bool {
        guard lhs.start == rhs.start, lhs.end == rhs.end else { return false }
        let left = lhs.lesson
        let right = rhs.lesson
        return left.hour.id == right.hour.id
            && left.subjectID == right.subjectID
            && left.subjectName == right.subjectName
            && left.subjectAbbrev == right.subjectAbbrev
            && left.teacherName == right.teacherName
            && left.teacherAbbrev == right.teacherAbbrev
            && left.roomName == right.roomName
            && left.roomAbbrev == right.roomAbbrev
            && left.groupIDs.sorted() == right.groupIDs.sorted()
            && left.groups.sorted() == right.groups.sorted()
            && left.cycles.sorted() == right.cycles.sorted()
            && left.theme == right.theme
            && left.hasHomework == right.hasHomework
            && left.change == right.change
            && left.changeKind == right.changeKind
    }

    private struct TimedLesson {
        let lesson: ScheduledLesson
        let start: Date
        let end: Date
    }
}
