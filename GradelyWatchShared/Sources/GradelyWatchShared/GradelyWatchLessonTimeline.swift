import Foundation

public enum GradelyWatchNowPage: Equatable, Sendable {
    case noTimetable
    case stale
    case inLesson(GradelyWatchTimetableLesson, progress: Double)
    case betweenLessons(next: GradelyWatchTimetableLesson, progress: Double, previous: GradelyWatchTimetableLesson?)
    case doneForToday
}

public extension GradelyWatchSyncCodec {
    static func progress(from start: Date, to end: Date, now: Date) -> Double {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else {
            return now >= end ? 1 : 0
        }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }

    static func todaysLessons(
        from timetable: GradelyWatchTimetable,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [GradelyWatchTimetableLesson] {
        let day = timetable.days.first { day in
            calendar.isDate(day.date ?? day.dayStart, inSameDayAs: now)
        }

        return (day?.lessons ?? []).sorted { first, second in
            if first.sortDate == second.sortDate {
                return first.id < second.id
            }
            return first.sortDate < second.sortDate
        }
    }

    static func remainingLessonsToday(
        from timetable: GradelyWatchTimetable?,
        now: Date = Date(),
        calendar: Calendar = .current,
        staleInterval: TimeInterval = staleInterval
    ) -> [GradelyWatchTimetableLesson] {
        guard let timetable, now.timeIntervalSince(timetable.cachedAt) <= staleInterval else {
            return []
        }

        return todaysLessons(from: timetable, now: now, calendar: calendar).filter { lesson in
            guard !lesson.isCanceled else { return false }
            guard let startDate = lesson.startDate else {
                return lesson.sortDate > now
            }
            return startDate > now
        }
    }

    static func nowPage(
        from timetable: GradelyWatchTimetable?,
        now: Date = Date(),
        calendar: Calendar = .current,
        staleInterval: TimeInterval = staleInterval
    ) -> GradelyWatchNowPage {
        guard let timetable else {
            return .noTimetable
        }

        if now.timeIntervalSince(timetable.cachedAt) > staleInterval {
            return .stale
        }

        let lessons = todaysLessons(from: timetable, now: now, calendar: calendar)
        guard !lessons.isEmpty else {
            return .doneForToday
        }

        if let current = lessons.first(where: { lesson in
            guard let startDate = lesson.startDate, let endDate = lesson.endDate else {
                return false
            }
            return startDate <= now && now <= endDate
        }) {
            let progress = progress(
                from: current.startDate ?? now,
                to: current.endDate ?? now,
                now: now
            )
            return .inLesson(current, progress: progress)
        }

        let upcoming = lessons.first { lesson in
            guard let startDate = lesson.startDate else {
                return lesson.sortDate > now
            }
            return startDate > now
        }

        guard let upcoming, let upcomingStart = upcoming.startDate else {
            return .doneForToday
        }

        let previous = lessons.last { lesson in
            guard let endDate = lesson.endDate else {
                return lesson.sortDate <= now
            }
            return endDate <= now
        }

        let gapStart = previous?.endDate ?? upcoming.dayStart
        return .betweenLessons(
            next: upcoming,
            progress: progress(from: gapStart, to: upcomingStart, now: now),
            previous: previous
        )
    }
}
