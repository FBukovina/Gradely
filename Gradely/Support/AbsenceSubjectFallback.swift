import Foundation

struct AbsenceLessonCandidate: Identifiable, Equatable {
    let id: String
    let dateKey: String
    let hourID: Int
    let hourCaption: String
    let timeRange: String
    let subjectKey: String
    let subjectName: String

    var displayTitle: String {
        timeRange.isEmpty ? "\(hourCaption). \(subjectName)" : "\(hourCaption). \(subjectName), \(timeRange)"
    }
}

struct AbsencePartialDayCandidate: Identifiable, Equatable {
    let dateKey: String
    let title: String
    let requiredSelectionCount: Int
    let selectedLessonIDs: [String]
    let lessons: [AbsenceLessonCandidate]

    var id: String { dateKey }
}

enum AbsenceSubjectFallback {
    struct Result: Equatable {
        let absences: [AbsencePerSubject]
        let stableIDHints: [String]
        let unresolvedPartialDays: [AbsencePartialDayCandidate]
        let appliedManualSelectionCount: Int

        static let empty = Result(
            absences: [],
            stableIDHints: [],
            unresolvedPartialDays: [],
            appliedManualSelectionCount: 0
        )
    }

    struct Term: Equatable {
        let start: Date
        let end: Date
        let weekStarts: [Date]
    }

    static func currentTerm(containing date: Date, calendar: Calendar = TimetableDates.weekCalendar) -> Term {
        term(containing: date, now: date, calendar: calendar)
    }

    static func term(
        for absences: [AbsenceDay],
        now: Date,
        calendar: Calendar = TimetableDates.weekCalendar
    ) -> Term {
        let dates = absences.compactMap { AbsenceOverrideProjection.schoolDate($0.date, calendar: calendar) }
        guard let latestAbsenceDate = dates.max() else {
            return currentTerm(containing: now, calendar: calendar)
        }

        return term(containing: latestAbsenceDate, now: now, calendar: calendar)
    }

    private static func term(
        containing date: Date,
        now: Date,
        calendar: Calendar
    ) -> Term {
        let bounds = termBounds(containing: date, calendar: calendar)
        let currentBounds = termBounds(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)

        let end: Date
        if calendar.isDate(bounds.start, inSameDayAs: currentBounds.start),
           calendar.isDate(bounds.termEnd, inSameDayAs: currentBounds.termEnd) {
            end = min(today, bounds.termEnd)
        } else {
            end = bounds.termEnd
        }

        return Term(start: bounds.start, end: end, weekStarts: weekStarts(from: bounds.start, through: end))
    }

    private static func termBounds(
        containing date: Date,
        calendar: Calendar
    ) -> (start: Date, termEnd: Date) {
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: day)
        let year = components.year ?? calendar.component(.year, from: day)
        let month = components.month ?? calendar.component(.month, from: day)

        let start: Date
        let termEnd: Date

        switch month {
        case 1:
            start = makeDate(year: year - 1, month: 9, day: 1, calendar: calendar)
            termEnd = makeDate(year: year, month: 1, day: 31, calendar: calendar)
        case 2...6:
            start = makeDate(year: year, month: 2, day: 1, calendar: calendar)
            termEnd = makeDate(year: year, month: 6, day: 30, calendar: calendar)
        case 7...8:
            start = makeDate(year: year, month: 2, day: 1, calendar: calendar)
            termEnd = makeDate(year: year, month: 6, day: 30, calendar: calendar)
        default:
            start = makeDate(year: year, month: 9, day: 1, calendar: calendar)
            termEnd = makeDate(year: year + 1, month: 1, day: 31, calendar: calendar)
        }

        return (start, termEnd)
    }

    static func makeAbsences(
        from response: AbsenceResponse,
        timetableResponses: [TimetableResponse],
        subjects: [Subject],
        validDateRange: ClosedRange<Date>? = nil,
        calendar: Calendar = TimetableDates.weekCalendar
    ) -> [AbsencePerSubject] {
        makeAbsenceResult(
            from: response,
            timetableResponses: timetableResponses,
            subjects: subjects,
            validDateRange: validDateRange,
            calendar: calendar
        ).absences
    }

    static func makeAbsenceResult(
        from response: AbsenceResponse,
        timetableResponses: [TimetableResponse],
        subjects: [Subject],
        manualSelections: AbsenceLessonSelections = .empty,
        manualAllocationsByDate: [String: [AbsenceOverrideAllocation]] = [:],
        validDateRange: ClosedRange<Date>? = nil,
        calendar: Calendar = TimetableDates.weekCalendar
    ) -> Result {
        guard response.absencesPerSubject.isEmpty else {
            return Result(
                absences: response.absencesPerSubject,
                stableIDHints: [],
                unresolvedPartialDays: [],
                appliedManualSelectionCount: 0
            )
        }
        guard !response.absences.isEmpty, !timetableResponses.isEmpty else { return .empty }

        var lessonResolver = AbsenceTimetableLessonResolver(subjects: subjects)
        var totals: [String: SubjectAbsenceTotal] = [:]
        var unresolvedPartialDays: [String: AbsencePartialDayCandidate] = [:]
        var appliedManualSelectionCount = 0

        let absenceByDate = Dictionary(
            response.absences.compactMap { day -> (String, AbsenceDay)? in
                guard let key = dateKey(day.date) else { return nil }
                return (key, day)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var assignedAnyFullDay = false

        for timetable in timetableResponses {
            for day in timetable.days {
                guard
                    let date = AbsenceOverrideProjection.schoolDate(day.date, calendar: calendar),
                    isDate(date, inside: validDateRange, calendar: calendar)
                else {
                    continue
                }

                let dateKey = AbsenceOverrideProjection.dateKey(day.date)
                let countableLessons = lessonResolver.countableLessons(
                    for: day,
                    in: timetable,
                    dateKey: dateKey
                )
                guard !countableLessons.isEmpty else { continue }

                for lesson in countableLessons {
                    if totals[lesson.subjectKey] == nil {
                        totals[lesson.subjectKey] = SubjectAbsenceTotal(
                            displayName: lesson.subjectName
                        )
                    }

                    totals[lesson.subjectKey]?.lessonsCount += 1
                }

                guard
                    let absenceDay = absenceByDate[dateKey],
                    absenceDay.fullDayAbsenceCount > 0
                else {
                    continue
                }

                // A confirmed original allocation replaces inference for this
                // day. It is counted below after every subject denominator is
                // known; hiding is a separate projection of that raw baseline.
                if let allocations = manualAllocationsByDate[dateKey],
                   completeAllocation(allocations, for: absenceDay) {
                    continue
                }

                if absenceDay.fullDayAbsenceCount >= countableLessons.count {
                    for lesson in countableLessons {
                        totals[lesson.subjectKey]?.base += 1
                        assignedAnyFullDay = true
                    }
                    continue
                }

                let validLessonIDs = Set(countableLessons.map(\.id))
                let selectedLessonIDs = manualSelections.selectedLessonIDs(for: dateKey).intersection(validLessonIDs)
                if selectedLessonIDs.count == absenceDay.fullDayAbsenceCount {
                    for lesson in countableLessons where selectedLessonIDs.contains(lesson.id) {
                        totals[lesson.subjectKey]?.base += 1
                        appliedManualSelectionCount += 1
                    }
                    assignedAnyFullDay = true
                } else {
                    unresolvedPartialDays[dateKey] = AbsencePartialDayCandidate(
                        dateKey: dateKey,
                        title: dayTitle(for: date),
                        requiredSelectionCount: min(absenceDay.fullDayAbsenceCount, countableLessons.count),
                        selectedLessonIDs: Array(selectedLessonIDs).sorted(),
                        lessons: countableLessons.map(\.candidate)
                    )
                }
            }
        }

        for (dateKey, allocations) in manualAllocationsByDate {
            guard let absenceDay = absenceByDate[dateKey],
                  completeAllocation(allocations, for: absenceDay) else { continue }
            if let date = AbsenceOverrideProjection.schoolDate(absenceDay.date, calendar: calendar),
               !isDate(date, inside: validDateRange, calendar: calendar) { continue }
            for allocation in allocations where allocation.category.contributesToBase {
                let key: String?
                if let subjectKey = allocation.subjectKey, totals[subjectKey] != nil {
                    key = subjectKey
                } else {
                    let matches = totals.keys.filter {
                        AbsenceOverrideProjection.normalizedSubjectName(totals[$0]?.displayName ?? "")
                            == AbsenceOverrideProjection.normalizedSubjectName(allocation.subjectName)
                    }
                    key = matches.count == 1 ? matches[0] : nil
                }
                // A manual subject with no taught-lesson denominator remains
                // unavailable instead of inventing a total or a percentage.
                guard let key else { continue }
                totals[key]?.base += 1
                appliedManualSelectionCount += 1
                assignedAnyFullDay = true
            }
        }

        let unresolvedDays = unresolvedPartialDays.values.sorted { $0.dateKey < $1.dateKey }
        guard assignedAnyFullDay || !unresolvedDays.isEmpty else { return .empty }

        let rows: [(absence: AbsencePerSubject, stableIDHint: String)] = lessonResolver.subjectKeys.compactMap { key in
            guard let total = totals[key], total.lessonsCount > 0 else { return nil }
            return (
                AbsencePerSubject(
                    subjectName: total.displayName,
                    lessonsCount: total.lessonsCount,
                    base: total.base,
                    late: 0,
                    soon: 0,
                    school: 0,
                    distanceTeaching: 0
                ),
                key
            )
        }

        return Result(
            absences: rows.map(\.absence),
            stableIDHints: rows.map(\.stableIDHint),
            unresolvedPartialDays: unresolvedDays,
            appliedManualSelectionCount: appliedManualSelectionCount
        )
    }

    private static func dayTitle(for date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.defaultDigits)
        )
    }

    private static func completeAllocation(_ allocations: [AbsenceOverrideAllocation], for day: AbsenceDay) -> Bool {
        Set(allocations.map(\.id)).count == allocations.count
            && AbsenceOverrideCategory.allCases.allSatisfy { category in
                category.count(in: day) >= 0
                    && allocations.filter { $0.category == category }.count == category.count(in: day)
            }
    }

    private static func weekStarts(from start: Date, through end: Date) -> [Date] {
        var weeks: [Date] = []
        var cursor = TimetableDates.monday(of: start)
        let last = TimetableDates.monday(of: end)

        while cursor <= last {
            weeks.append(cursor)
            guard let next = TimetableDates.weekCalendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        return weeks
    }

    private static func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    private static func dateKey(_ string: String) -> String? {
        let fallback = AbsenceOverrideProjection.dateKey(string)
        return fallback.isEmpty ? nil : fallback
    }

    private static func isDate(
        _ date: Date,
        inside range: ClosedRange<Date>?,
        calendar: Calendar
    ) -> Bool {
        guard let range else { return true }
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: range.lowerBound)
            && day <= calendar.startOfDay(for: range.upperBound)
    }
}

private struct SubjectAbsenceTotal {
    let displayName: String
    var lessonsCount = 0
    var base = 0

    init(displayName: String) {
        self.displayName = displayName
    }
}

private extension AbsenceDay {
    var fullDayAbsenceCount: Int {
        unsolved + ok + missed
    }
}
