import Foundation

// MARK: - Periods

/// What one Gradey Recap covers.
enum RecapKind: String, Hashable, CaseIterable {
    case month
    case quarter
    case semester
    case calendarYear

    /// The Today row shows the biggest recap when two are out at once.
    var priority: Int {
        switch self {
        case .calendarYear: 3
        case .semester: 2
        case .quarter: 1
        case .month: 0
        }
    }
}

/// A month, quarter, semester or calendar year, in school time (Prague).
struct RecapPeriod: Identifiable, Hashable {
    let kind: RecapKind
    /// Month 1–12, quarter 1 or 3, semester 1 or 2; unused for a calendar year.
    let number: Int
    /// The calendar year for months and calendar years; the school year's
    /// first year ("2026" for 2026/27) for quarters and semesters.
    let year: Int
    let start: Date
    /// The day after the last one.
    let end: Date

    var id: String { "\(kind.rawValue)-\(year)-\(number)" }

    /// The school year this period is listed under in the Recap list.
    var schoolYearStart: Int {
        switch kind {
        case .month: number >= 9 ? year : year - 1
        case .quarter, .semester, .calendarYear: year
        }
    }

    func isOngoing(at now: Date) -> Bool { now < end }

    static func month(_ month: Int, of year: Int) -> RecapPeriod {
        let start = RecapCalendar.date(year, month, 1)
        return RecapPeriod(kind: .month, number: month, year: year, start: start,
                           end: RecapCalendar.calendar.date(byAdding: .month, value: 1, to: start) ?? start)
    }

    /// The 1st quarter runs to mid-November, the 3rd to mid-April, when
    /// schools hold their quarterly reviews.
    static func quarter(_ quarter: Int, schoolYear startYear: Int) -> RecapPeriod {
        let start = quarter == 1 ? RecapCalendar.date(startYear, 9, 1) : RecapCalendar.date(startYear + 1, 2, 1)
        let end = quarter == 1 ? RecapCalendar.date(startYear, 11, 16) : RecapCalendar.date(startYear + 1, 4, 16)
        return RecapPeriod(kind: .quarter, number: quarter, year: startYear, start: start, end: end)
    }

    /// Same boundaries as `ReportCardPeriod`: September to January is the first.
    static func semester(_ semester: Int, schoolYear startYear: Int) -> RecapPeriod {
        let start = semester == 1 ? RecapCalendar.date(startYear, 9, 1) : RecapCalendar.date(startYear + 1, 2, 1)
        let end = semester == 1 ? RecapCalendar.date(startYear + 1, 2, 1) : RecapCalendar.date(startYear + 1, 7, 1)
        return RecapPeriod(kind: .semester, number: semester, year: startYear, start: start, end: end)
    }

    static func calendarYear(_ year: Int) -> RecapPeriod {
        RecapPeriod(kind: .calendarYear, number: 0, year: year,
                    start: RecapCalendar.date(year, 1, 1), end: RecapCalendar.date(year + 1, 1, 1))
    }

    /// The semesters whose marks and absence this period reads.
    var semesters: [ReportCardPeriod] {
        var periods: [ReportCardPeriod] = []
        var day = start
        while day < end {
            let period = ReportCardPeriod(containing: day)
            if !periods.contains(period) { periods.append(period) }
            day = RecapCalendar.calendar.date(byAdding: .month, value: 1, to: day) ?? end
        }
        return periods
    }
}

/// When each recap comes out, and when Today points at it.
enum RecapCalendar {
    static var calendar: Calendar { Homework.schoolCalendar }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    struct Window {
        /// From this day the period is in the Recap list.
        let listedFrom: Date
        /// Today shows it from `listedFrom` up to this day.
        let todayUntil: Date
    }

    static func window(for period: RecapPeriod) -> Window {
        let y = period.year
        switch period.kind {
        case .month:
            return Window(listedFrom: period.end, todayUntil: adding(days: 7, to: period.end))
        case .quarter:
            let year = period.number == 1 ? y : y + 1
            let month = period.number == 1 ? 11 : 4
            return Window(listedFrom: date(year, month, 10), todayUntil: date(year, month, 25))
        case .semester:
            return period.number == 1
                ? Window(listedFrom: date(y + 1, 1, 20), todayUntil: date(y + 1, 2, 4))
                : Window(listedFrom: date(y + 1, 6, 15), todayUntil: date(y + 1, 6, 30))
        case .calendarYear:
            return Window(listedFrom: date(y, 12, 15), todayUntil: date(y + 1, 1, 6))
        }
    }

    /// Every recap of this school year and the previous one, plus the last two calendar years.
    static func candidates(around now: Date) -> [RecapPeriod] {
        let startYear = ReportCardPeriod(containing: now).startYear
        var periods: [RecapPeriod] = []
        for schoolYear in [startYear - 1, startYear] {
            for month in [9, 10, 11, 12] { periods.append(.month(month, of: schoolYear)) }
            for month in 1...6 { periods.append(.month(month, of: schoolYear + 1)) }
            periods.append(.quarter(1, schoolYear: schoolYear))
            periods.append(.quarter(3, schoolYear: schoolYear))
            periods.append(.semester(1, schoolYear: schoolYear))
            periods.append(.semester(2, schoolYear: schoolYear))
        }
        let year = calendar.component(.year, from: now)
        periods.append(.calendarYear(year - 1))
        periods.append(.calendarYear(year))
        return periods
    }

    /// Out by now, newest first.
    static func listed(at now: Date) -> [RecapPeriod] {
        candidates(around: now)
            .filter { window(for: $0).listedFrom <= now }
            .sorted { lhs, rhs in
                let left = window(for: lhs).listedFrom, right = window(for: rhs).listedFrom
                return left != right ? left > right : lhs.kind.priority > rhs.kind.priority
            }
    }

    /// The ones Today points at right now, biggest first.
    static func featured(at now: Date) -> [RecapPeriod] {
        candidates(around: now)
            .filter { window(for: $0).listedFrom <= now && now < window(for: $0).todayUntil }
            .sorted { $0.kind.priority > $1.kind.priority }
    }

    private static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}

// MARK: - Archive

/// Bakaláři only returns the current semester's marks and absence, so every
/// semester the app sees is kept here for recaps of earlier periods.
struct RecapArchive: Codable, Equatable {
    static let cachePrefix = "recap-archive"
    /// Older school years are dropped.
    static let keptSchoolYears = 3

    /// By `key(for:)`, e.g. "2026/27-1".
    var marks: [String: MarksResponse] = [:]
    var absence: [String: AbsenceResponse] = [:]

    static func key(for period: ReportCardPeriod) -> String {
        period.schoolYear + "-" + String(period.semester)
    }

    static func period(forKey key: String) -> ReportCardPeriod? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let semester = Int(parts[1]),
              let startYear = Int(parts[0].split(separator: "/").first ?? "") else { return nil }
        return ReportCardPeriod(startYear: startYear, semester: semester)
    }

    /// The semester most of the marks fall in; nil without dated marks.
    static func semester(ofMarks subjects: [Subject]) -> ReportCardPeriod? {
        let periods = subjects.flatMap(\.marks).compactMap { MarkDateFormatter.date(from: $0.markDate) }
            .map { ReportCardPeriod(containing: $0) }
        let counts = Dictionary(periods.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : (lhs.key.startYear, lhs.key.semester) < (rhs.key.startYear, rhs.key.semester)
        }?.key
    }

    /// The semester of the latest absence day; nil without any.
    static func semester(ofAbsence response: AbsenceResponse) -> ReportCardPeriod? {
        response.absences.compactMap { MarkDateFormatter.date(from: $0.date) }.max()
            .map { ReportCardPeriod(containing: $0) }
    }

    mutating func prune(now: Date) {
        let oldest = ReportCardPeriod(containing: now).startYear - (Self.keptSchoolYears - 1)
        let isKept: (String) -> Bool = { Self.period(forKey: $0).map { $0.startYear >= oldest } ?? false }
        marks = marks.filter { isKept($0.key) }
        absence = absence.filter { isKept($0.key) }
    }
}

// MARK: - Result

struct RecapSubjectStat: Identifiable, Equatable {
    let id: String
    let name: String
    let average: Double
    let markCount: Int
}

enum RecapMoment: Equatable {
    case onesStreak(count: Int)
    case comeback(subject: String, from: Double, to: Double)
    case heaviestMark(markText: String, subject: String, weight: Double)
    case busiestDay(date: Date, count: Int)
}

struct RecapAbsence: Equatable {
    let counts: AbsenceCounts
    let topSubject: String?
    let topSubjectHours: Int
}

struct RecapTimetable: Equatable {
    let lessons: Int
    let canceled: Int
    let substitutions: Int
    let topCanceledSubject: String?
}

struct RecapReportCard: Equatable {
    let average: Double
    /// False once the teachers closed the report card.
    let isEstimate: Bool
    let ones: Int
    let borderline: Int
}

/// The calendar-year recap's look back at last school year's spring.
struct RecapLastYear: Equatable {
    let springTerm: String
    let springAverage: Double?
    let springAbsentHours: Double?
    let autumnAverage: Double?
    let autumnAbsentHours: Int?
}

struct RecapComparison: Equatable {
    enum Basis: Equatable {
        case previousMonth
        case previousReportCard
    }

    let basis: Basis
    let average: Double
}

/// The Wrapped-style type, picked by the first rule that fits.
enum RecapPersonality: Equatable {
    case straightAs
    case comeback
    case rollercoaster
    case lastMinute
    case specialty(subject: String)
    case steady
}

enum RecapSlide: String, Hashable, CaseIterable {
    case intro
    case marks
    case average
    case topSubject
    case toughestSubject
    case moments
    case absence
    case timetable
    case personality
    case reportCard
    case lastYear
    case summary
}

struct Recap: Equatable {
    let period: RecapPeriod
    let isOngoing: Bool
    let markCount: Int
    /// Marks 1 to 5, ±; index 0 holds the ones.
    let distribution: [Int]
    /// Points and verbal marks such as N or X.
    let otherMarks: Int
    let average: Double?
    let comparison: RecapComparison?
    let topSubject: RecapSubjectStat?
    let toughestSubject: RecapSubjectStat?
    let moments: [RecapMoment]
    let absence: RecapAbsence?
    let timetable: RecapTimetable?
    let personality: RecapPersonality?
    let reportCard: RecapReportCard?
    let lastYear: RecapLastYear?
    /// A calendar year whose spring marks are no longer on this device.
    let springFromReportCard: Bool

    var hasContent: Bool { markCount > 0 || (absence?.counts.total ?? 0) > 0 }

    var slides: [RecapSlide] {
        let isMonth = period.kind == .month
        return RecapSlide.allCases.filter { slide in
            switch slide {
            case .intro, .summary: true
            case .marks: markCount > 0
            case .average: average != nil
            case .topSubject: topSubject != nil
            case .toughestSubject: !isMonth && toughestSubject != nil
            case .moments: !isMonth && !moments.isEmpty
            case .absence: absence != nil
            case .timetable: (timetable?.lessons ?? 0) > 0
            case .personality: !isMonth && personality != nil
            case .reportCard: reportCard != nil
            case .lastYear: lastYear != nil
            }
        }
    }
}
