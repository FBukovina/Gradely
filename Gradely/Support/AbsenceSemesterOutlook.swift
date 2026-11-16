import Foundation

/// What the Absence subject rows say when "how much can I miss this
/// semester" is on in Settings.
enum AbsenceSemesterAllowance: Equatable {
    /// This many more lessons can be missed and the subject still ends the
    /// semester under the school limit.
    case canMiss(Int)
    /// Exactly at the edge: one more missed lesson would end over the limit.
    case noMoreMisses
    /// Over the limit at the end of the semester even with full attendance.
    case overEvenWithFullAttendance
}

/// The lessons each subject still has in the timetable from tomorrow to the
/// end of the semester. Bakaláři's per-subject lesson count only covers
/// lessons already taught, so the semester's total is that count plus these.
struct AbsenceSemesterOutlook: Equatable {
    static let settingKey = "settings.showAbsenceSemesterAllowance"

    struct SubjectLessons: Equatable {
        let key: String
        /// Normalized subject names and abbreviations an absence row may use.
        let aliases: Set<String>
        var count: Int
    }

    let termEnd: Date
    let subjects: [SubjectLessons]

    static func make(
        timetables: [TimetableResponse],
        markSubjects: [Subject],
        from start: Date,
        through termEnd: Date,
        calendar: Calendar = TimetableDates.weekCalendar
    ) -> AbsenceSemesterOutlook {
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: termEnd)
        var resolver = AbsenceTimetableLessonResolver(subjects: markSubjects)
        var seenDateKeys: Set<String> = []
        var byKey: [String: SubjectLessons] = [:]
        var order: [String] = []

        for timetable in timetables {
            var entityAliases: [String: Set<String>] = [:]
            for entity in timetable.subjects {
                let key = "raw-" + AbsenceTimetableLessonResolver.normalized(entity.id)
                entityAliases[key, default: []].formUnion(
                    [entity.name, entity.abbrev]
                        .map(AbsenceTimetableLessonResolver.normalized)
                        .filter { !$0.isEmpty }
                )
            }

            for day in timetable.days {
                guard Self.countsLessons(DayType(apiValue: day.dayType)),
                      let date = AbsenceOverrideProjection.schoolDate(day.date, calendar: calendar),
                      date >= firstDay, date <= lastDay
                else { continue }
                let dateKey = AbsenceOverrideProjection.dateKey(for: date, calendar: calendar)
                guard seenDateKeys.insert(dateKey).inserted else { continue }

                for lesson in resolver.countableLessons(for: day, in: timetable, dateKey: dateKey) {
                    var aliases = entityAliases[lesson.subjectKey] ?? []
                    let name = AbsenceTimetableLessonResolver.normalized(lesson.subjectName)
                    if !name.isEmpty { aliases.insert(name) }

                    if var existing = byKey[lesson.subjectKey] {
                        existing.count += 1
                        byKey[lesson.subjectKey] = SubjectLessons(
                            key: existing.key,
                            aliases: existing.aliases.union(aliases),
                            count: existing.count
                        )
                    } else {
                        byKey[lesson.subjectKey] = SubjectLessons(key: lesson.subjectKey, aliases: aliases, count: 1)
                        order.append(lesson.subjectKey)
                    }
                }
            }
        }

        return AbsenceSemesterOutlook(termEnd: lastDay, subjects: order.compactMap { byKey[$0] })
    }

    /// Timetable lessons the row's subject has left, or nil when the timetable
    /// has no subject of that name (so the row keeps its usual line).
    func remainingLessons(for row: AbsenceSubjectSummary) -> Int? {
        let name = AbsenceTimetableLessonResolver.normalized(row.subjectName)
        var matches = subjects.filter { !name.isEmpty && $0.aliases.contains(name) }
        if matches.isEmpty {
            matches = subjects.filter { subject in
                row.stableID == subject.key
                    || row.stableID.hasSuffix("-\(AbsenceTimetableLessonResolver.storageSafe(subject.key))")
            }
        }
        guard !matches.isEmpty else { return nil }
        return matches.reduce(0) { $0 + $1.count }
    }

    func allowance(for row: AbsenceSubjectSummary, threshold: Double?) -> AbsenceSemesterAllowance? {
        guard let remaining = remainingLessons(for: row) else { return nil }
        return Self.allowance(
            missed: row.base,
            taught: row.lessonsCount,
            remaining: remaining,
            threshold: AbsenceRiskSummary.normalizedThreshold(threshold)
        )
    }

    /// Like the rest of the app, reaching the threshold counts as over it, so
    /// the allowance keeps the semester's share strictly under the limit.
    static func allowance(
        missed: Int,
        taught: Int,
        remaining: Int,
        threshold: Double?
    ) -> AbsenceSemesterAllowance? {
        guard let threshold, threshold > 0, threshold < 100 else { return nil }
        let total = taught + remaining
        guard total > 0 else { return nil }

        let limit = threshold / 100 * Double(total)
        // Most missed lessons strictly below the limit.
        let maxMissed = Int((limit - 1e-9).rounded(.up)) - 1
        if maxMissed < missed { return .overEvenWithFullAttendance }
        let allowed = min(maxMissed - missed, remaining)
        return allowed > 0 ? .canMiss(allowed) : .noMoreMisses
    }

    private static func countsLessons(_ dayType: DayType) -> Bool {
        switch dayType {
        case .workDay, .undefined: true
        case .weekend, .celebration, .holiday, .directorDay: false
        }
    }
}
