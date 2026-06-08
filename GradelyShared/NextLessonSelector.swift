import Foundation

enum NextLessonSelector {
    static let defaultStaleInterval: TimeInterval = 7 * 24 * 60 * 60

    static func select(
        snapshot: NextLessonWidgetSnapshot?,
        now: Date = Date(),
        staleInterval: TimeInterval = defaultStaleInterval
    ) -> NextLessonWidgetSelection {
        guard let snapshot else {
            return .noSnapshot
        }

        if now.timeIntervalSince(snapshot.cachedAt) > staleInterval {
            return .stale
        }

        let lessons = snapshot.lessons.sorted { first, second in
            if first.sortDate == second.sortDate {
                return first.id < second.id
            }
            return first.sortDate < second.sortDate
        }

        guard !lessons.isEmpty else {
            return .noLessons
        }

        if let current = lessons.first(where: { lesson in
            guard let startDate = lesson.startDate, let endDate = lesson.endDate else {
                return false
            }
            return startDate <= now && now <= endDate
        }) {
            return .lesson(current, timing: .current)
        }

        if let upcoming = lessons.first(where: { lesson in
            guard let startDate = lesson.startDate else {
                return lesson.sortDate >= now
            }
            return startDate > now
        }) {
            return .lesson(upcoming, timing: .upcoming)
        }

        return .noLessons
    }

    static func timelineDates(
        snapshot: NextLessonWidgetSnapshot?,
        after date: Date,
        limit: Int = 16
    ) -> [Date] {
        guard let snapshot else {
            return []
        }

        let eventDates = snapshot.lessons
            .flatMap { [$0.startDate, $0.endDate].compactMap { $0 } }
            .filter { $0 > date }
            .sorted()

        var seen = Set<Date>()
        var uniqueDates: [Date] = []

        for eventDate in eventDates where !seen.contains(eventDate) {
            seen.insert(eventDate)
            uniqueDates.append(eventDate)
            if uniqueDates.count == limit {
                break
            }
        }

        return uniqueDates
    }
}
