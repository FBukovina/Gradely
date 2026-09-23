import Foundation

enum PlannerNextLessonSelector {
    static func nextDate(after reference: PlannerLessonReference, in weeks: [TimetableWeek], calendar: Calendar = .current) -> Date? {
        guard let subjectID = reference.subjectID, !subjectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let start = reference.start else { return nil }
        return weeks.flatMap(\.days).flatMap { day -> [Date] in
            guard day.dayType.isSchoolDay, let date = day.date else { return [] }
            return day.lessons.compactMap { lesson in
                guard !lesson.isCanceled, lesson.subjectID == subjectID,
                      reference.groupIDs.isEmpty || lesson.groupIDs.isEmpty
                        || !Set(reference.groupIDs).isDisjoint(with: lesson.groupIDs),
                      let next = TimetableLessonTiming.date(lesson.hour.beginTime, on: date, calendar: calendar),
                      next > start else { return nil }
                return next
            }
        }.min()
    }
}

/// Uses the repository's existing mapper, cache, provider support and timeout. No recurrence guesses.
@MainActor
struct PlannerLessonResolver {
    let loadWeek: (Date) async throws -> TimetableWeek
    let cachedWeek: (Date) -> TimetableWeek?
    let currentScope: () -> SchoolDataScope?

    init(repository: SchoolRepository) {
        loadWeek = { try await repository.loadTimetable(weekContaining: $0, publishSummaries: false) }
        cachedWeek = { repository.loadCachedTimetable(weekContaining: $0, publishSummaries: false) }
        currentScope = { (try? repository.currentStoredSession()).map(SchoolDataScope.init(session:)) }
    }

    init(
        loadWeek: @escaping (Date) async throws -> TimetableWeek,
        cachedWeek: @escaping (Date) -> TimetableWeek?,
        currentScope: @escaping () -> SchoolDataScope?
    ) {
        self.loadWeek = loadWeek
        self.cachedWeek = cachedWeek
        self.currentScope = currentScope
    }

    /// Search the linked week and four following weeks. A missing week stops the search: a later
    /// result cannot be called the "next" lesson when an earlier week's schedule is unavailable.
    func nextDate(after item: PlannerItem, displayedWeek: TimetableWeek? = nil) async throws -> Date? {
        guard let reference = item.lesson, let start = reference.start,
              let subjectID = reference.subjectID, !subjectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        for offset in 0...4 {
            try Task.checkCancellation()
            guard currentScope() == reference.scope else { throw PlannerError.timetableUnavailable }
            let anchor = TimetableDates.addingWeeks(offset, to: TimetableDates.monday(of: start))
            let week: TimetableWeek
            if offset == 0, let displayedWeek,
               TimetableDates.apiDateString(displayedWeek.weekStart) == TimetableDates.apiDateString(anchor),
               displayedWeek.days.contains(where: { $0.date != nil }) {
                week = displayedWeek
            } else {
                do {
                    week = try await loadWeek(anchor)
                } catch {
                    try Task.checkCancellation()
                    guard let cached = cachedWeek(anchor) else { throw PlannerError.timetableUnavailable }
                    week = cached
                }
            }
            guard currentScope() == reference.scope else { throw PlannerError.timetableUnavailable }
            if let date = PlannerNextLessonSelector.nextDate(after: reference, in: [week], calendar: item.calendar) {
                return date
            }
        }
        return nil
    }
}
