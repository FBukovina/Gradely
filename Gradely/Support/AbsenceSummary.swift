import Foundation

struct AbsenceCounts: Equatable {
    var unsolved: Int
    var ok: Int
    var missed: Int
    var late: Int
    var soon: Int
    var school: Int
    var distanceTeaching: Int

    static let zero = AbsenceCounts(
        unsolved: 0,
        ok: 0,
        missed: 0,
        late: 0,
        soon: 0,
        school: 0,
        distanceTeaching: 0
    )

    init(day: AbsenceDay) {
        self.init(
            unsolved: day.unsolved,
            ok: day.ok,
            missed: day.missed,
            late: day.late,
            soon: day.soon,
            school: day.school,
            distanceTeaching: day.distanceTeaching
        )
    }

    init(
        unsolved: Int,
        ok: Int,
        missed: Int,
        late: Int,
        soon: Int,
        school: Int,
        distanceTeaching: Int
    ) {
        self.unsolved = unsolved
        self.ok = ok
        self.missed = missed
        self.late = late
        self.soon = soon
        self.school = school
        self.distanceTeaching = distanceTeaching
    }

    var total: Int {
        unsolved + ok + missed + late + soon + school + distanceTeaching
    }

    mutating func add(_ other: AbsenceCounts) {
        unsolved += other.unsolved
        ok += other.ok
        missed += other.missed
        late += other.late
        soon += other.soon
        school += other.school
        distanceTeaching += other.distanceTeaching
    }
}

struct AbsenceDaySummary: Identifiable, Equatable {
    let id: String
    let date: Date?
    let title: String
    let counts: AbsenceCounts
}

struct AbsenceMonthSummary: Identifiable, Equatable {
    let id: String
    let monthDate: Date
    let title: String
    let counts: AbsenceCounts
}

struct AbsenceSubjectSummary: Identifiable, Equatable {
    let id: String
    let subjectName: String
    let lessonsCount: Int
    let base: Int
    let absencePercentage: Double
    let exceedsThreshold: Bool

    init(absence: AbsencePerSubject, threshold: Double) {
        subjectName = absence.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        id = subjectName.isEmpty ? absence.id : subjectName
        lessonsCount = absence.lessonsCount
        base = absence.base
        absencePercentage = absence.absencePercentage

        let normalizedThreshold = threshold > 0 && threshold <= 1 ? threshold * 100 : threshold
        exceedsThreshold = normalizedThreshold > 0 && absencePercentage >= normalizedThreshold
    }
}

enum AbsenceSummary {
    static func totalCounts(for days: [AbsenceDay]) -> AbsenceCounts {
        days.reduce(into: .zero) { total, day in
            total.add(AbsenceCounts(day: day))
        }
    }

    static func daySummaries(
        for days: [AbsenceDay],
        calendar: Calendar = .current
    ) -> [AbsenceDaySummary] {
        days
            .map { day in
                let date = MarkDateFormatter.date(from: day.date)
                return AbsenceDaySummary(
                    id: day.id,
                    date: date,
                    title: dayTitle(for: date, fallback: day.date),
                    counts: AbsenceCounts(day: day)
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case (.some(let lhsDate), .some(let rhsDate)):
                    return lhsDate < rhsDate
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.id < rhs.id
                }
            }
    }

    static func monthSummaries(
        for days: [AbsenceDay],
        calendar: Calendar = .current
    ) -> [AbsenceMonthSummary] {
        var grouped: [Date: AbsenceCounts] = [:]

        for day in days {
            guard let date = MarkDateFormatter.date(from: day.date) else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let month = calendar.date(from: components) else { continue }
            grouped[month, default: .zero].add(AbsenceCounts(day: day))
        }

        return grouped.map { month, counts in
            AbsenceMonthSummary(
                id: TimetableDates.apiDateString(month),
                monthDate: month,
                title: month.formatted(.dateTime.month(.wide).year()),
                counts: counts
            )
        }
        .sorted { $0.monthDate < $1.monthDate }
    }

    static func subjectSummaries(
        for absences: [AbsencePerSubject],
        threshold: Double
    ) -> [AbsenceSubjectSummary] {
        absences
            .map { AbsenceSubjectSummary(absence: $0, threshold: threshold) }
            .sorted {
                if $0.exceedsThreshold != $1.exceedsThreshold {
                    return $0.exceedsThreshold && !$1.exceedsThreshold
                }
                if $0.absencePercentage != $1.absencePercentage {
                    return $0.absencePercentage > $1.absencePercentage
                }
                return $0.subjectName.localizedCaseInsensitiveCompare($1.subjectName) == .orderedAscending
            }
    }

    private static func dayTitle(for date: Date?, fallback: String) -> String {
        guard let date else {
            return String(fallback.split(separator: "T").first ?? "")
        }

        return date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.defaultDigits)
        )
    }
}
