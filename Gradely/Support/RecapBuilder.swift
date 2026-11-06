import Foundation

/// One semester of school data as the device has it.
struct RecapSemester {
    let period: ReportCardPeriod
    let subjects: [Subject]
    let absence: AbsenceResponse?
}

struct RecapInput {
    var semesters: [RecapSemester] = []
    var reportCards: [ReportCardTerm] = []
    /// Nil until the period's timetable weeks were loaded.
    var timetableWeeks: [TimetableWeek]?
    /// The live semester's missed lessons by date key, for the absence slide.
    var absenceLessons: [String: AbsenceDayLessons]?
    var now: Date
}

/// Turns a period's marks, absence and timetable into a `Recap`. Everything
/// is computed on the device.
enum RecapBuilder {
    static func build(_ period: RecapPeriod, input: RecapInput) -> Recap {
        let calendar = RecapCalendar.calendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: input.now)) ?? input.now
        let end = min(period.end, tomorrow)
        let semesters = input.semesters.filter { period.semesters.contains($0.period) }
        let entries = markEntries(in: semesters, from: period.start, to: end)
        let numeric = entries.filter { $0.value != nil }

        var distribution = Array(repeating: 0, count: 5)
        var otherMarks = 0
        for entry in entries {
            if let bucket = entry.bucket { distribution[bucket - 1] += 1 } else { otherMarks += 1 }
        }

        let subjects = subjectStats(numeric, semesters: semesters, from: period.start, to: end)
        let average = mean(subjects.map(\.average))
        let ranked = subjects.filter { $0.markCount >= 2 }.sorted {
            $0.average != $1.average ? $0.average < $1.average : $0.markCount > $1.markCount
        }
        let top = ranked.first
        let toughest = ranked.count >= 2 && (ranked.last?.average ?? 0) - (top?.average ?? 0) >= 0.01 ? ranked.last : nil
        let midpoint = Date(timeIntervalSince1970: (period.start.timeIntervalSince1970 + end.timeIntervalSince1970) / 2)
        let isOngoing = period.isOngoing(at: input.now)

        let card = period.kind == .semester ? reportCard(for: period, semesters: semesters, terms: input.reportCards) : nil
        let lookBack = period.kind == .calendarYear ? lastYear(for: period, input: input, end: end) : nil
        let springSemester = ReportCardPeriod(startYear: period.year - 1, semester: 2)

        return Recap(
            period: period,
            isOngoing: isOngoing,
            markCount: entries.count,
            distribution: distribution,
            otherMarks: otherMarks,
            average: average,
            comparison: comparison(for: period, input: input),
            topSubject: top,
            toughestSubject: toughest,
            moments: moments(entries: entries, numeric: numeric, midpoint: midpoint),
            absence: absence(for: period, semesters: semesters, lessons: input.absenceLessons, end: end),
            timetable: input.timetableWeeks.flatMap { timetable($0, from: period.start, to: end) },
            personality: personality(numeric: numeric, subjects: ranked, average: average, period: period,
                                     midpoint: midpoint, end: end, isOngoing: isOngoing),
            reportCard: card,
            lastYear: lookBack,
            springFromReportCard: period.kind == .calendarYear
                && lookBack != nil
                && !input.semesters.contains { $0.period == springSemester && !$0.subjects.flatMap(\.marks).isEmpty }
        )
    }

    // MARK: - Marks

    struct MarkEntry {
        let id: String
        let date: Date
        let subjectID: String
        let subjectName: String
        let markText: String
        /// Nil for marks that don't count towards the average.
        let value: Double?
        let weight: Double
        /// 1–5 for "1"–"5" with or without ±; nil for points and verbal marks.
        let bucket: Int?
    }

    static func markEntries(in semesters: [RecapSemester], from start: Date, to end: Date) -> [MarkEntry] {
        var seen: Set<String> = []
        var entries: [MarkEntry] = []
        for semester in semesters {
            for subject in semester.subjects {
                let prepared = Dictionary(GradeMath.prepare(subject).marks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for mark in subject.marks {
                    guard let date = MarkDateFormatter.date(from: mark.markDate), date >= start, date < end,
                          seen.insert(mark.id).inserted else { continue }
                    let text = mark.markText.trimmingCharacters(in: .whitespacesAndNewlines)
                    entries.append(MarkEntry(
                        id: mark.id,
                        date: date,
                        subjectID: subject.id,
                        subjectName: subject.trimmedName,
                        markText: text,
                        value: prepared[mark.id]?.value,
                        weight: prepared[mark.id]?.weight.value ?? 1,
                        bucket: mark.isPoints ? nil : bucket(for: text)
                    ))
                }
            }
        }
        return entries.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id }
    }

    static func bucket(for markText: String) -> Int? {
        guard let first = markText.first, let digit = first.wholeNumberValue, (1...5).contains(digit) else { return nil }
        let rest = markText.dropFirst()
        return rest.isEmpty || rest == "+" || rest == "-" ? digit : nil
    }

    /// Weighted per subject; a subject wholly inside the period keeps its
    /// official Bakaláři average, so a semester recap matches the Marks screen.
    private static func subjectStats(_ numeric: [MarkEntry], semesters: [RecapSemester], from start: Date, to end: Date) -> [RecapSubjectStat] {
        let bySubject = Dictionary(grouping: numeric, by: \.subjectID)
        return bySubject.compactMap { subjectID, marks -> RecapSubjectStat? in
            guard let name = marks.last?.subjectName else { return nil }
            var average = weightedMean(marks)
            let sources = semesters.compactMap { $0.subjects.first { $0.id == subjectID } }
            if sources.count == 1, let subject = sources.first {
                let prepared = GradeMath.prepare(subject)
                let inside = prepared.marks.allSatisfy { mark in mark.date.map { $0 >= start && $0 < end } ?? false }
                if inside, let official = prepared.displayAverage { average = official }
            }
            return average.map { RecapSubjectStat(id: subjectID, name: name, average: $0, markCount: marks.count) }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func weightedMean(_ entries: [MarkEntry]) -> Double? {
        let totalWeight = entries.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let average = entries.reduce(0) { $0 + ($1.value ?? 0) * $1.weight } / totalWeight
        return average.isFinite ? average : nil
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Mean of the subject averages, like `GradeMath.overallAverage`.
    private static func average(in semesters: [RecapSemester], from start: Date, to end: Date) -> Double? {
        let numeric = markEntries(in: semesters, from: start, to: end).filter { $0.value != nil }
        return mean(subjectStats(numeric, semesters: semesters, from: start, to: end).map(\.average))
    }

    private static func comparison(for period: RecapPeriod, input: RecapInput) -> RecapComparison? {
        switch period.kind {
        case .month:
            guard period.number != 9 else { return nil }
            let previous = RecapPeriod.month(period.number == 1 ? 12 : period.number - 1,
                                             of: period.number == 1 ? period.year - 1 : period.year)
            let semesters = input.semesters.filter { previous.semesters.contains($0.period) }
            return average(in: semesters, from: previous.start, to: previous.end)
                .map { RecapComparison(basis: .previousMonth, average: $0) }
        case .quarter, .semester:
            let previous = period.number == 1
                ? ReportCardPeriod(startYear: period.year - 1, semester: 2)
                : ReportCardPeriod(startYear: period.year, semester: 1)
            return input.reportCards.first { $0.matches(previous) }?.average
                .map { RecapComparison(basis: .previousReportCard, average: $0) }
        case .calendarYear:
            return nil
        }
    }

    // MARK: - Moments

    private static func moments(entries: [MarkEntry], numeric: [MarkEntry], midpoint: Date) -> [RecapMoment] {
        var moments: [RecapMoment] = []

        var longest = 0, current = 0
        for entry in entries where entry.bucket != nil {
            current = entry.bucket == 1 ? current + 1 : 0
            longest = max(longest, current)
        }
        if longest >= 3 { moments.append(.onesStreak(count: longest)) }

        let comebacks = Dictionary(grouping: numeric, by: \.subjectID).compactMap { _, marks -> (String, Double, Double)? in
            let first = marks.filter { $0.date < midpoint }, second = marks.filter { $0.date >= midpoint }
            guard first.count >= 2, second.count >= 2,
                  let before = weightedMean(first), let after = weightedMean(second), before - after >= 0.3,
                  let name = marks.last?.subjectName else { return nil }
            return (name, before, after)
        }
        if let best = comebacks.max(by: { $0.1 - $0.2 < $1.1 - $1.2 }) {
            moments.append(.comeback(subject: best.0, from: best.1, to: best.2))
        }

        let weights = numeric.map(\.weight)
        if let heaviest = numeric.max(by: { $0.weight != $1.weight ? $0.weight < $1.weight : $0.date > $1.date }),
           let lightest = weights.min(), heaviest.weight > lightest {
            moments.append(.heaviestMark(markText: heaviest.markText, subject: heaviest.subjectName, weight: heaviest.weight))
        }

        let days = Dictionary(grouping: entries) { RecapCalendar.calendar.startOfDay(for: $0.date) }
        if let busiest = days.max(by: { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key }),
           busiest.value.count >= 2 {
            moments.append(.busiestDay(date: busiest.key, count: busiest.value.count))
        }
        return Array(moments.prefix(3))
    }

    // MARK: - Personality

    private static func personality(
        numeric: [MarkEntry], subjects: [RecapSubjectStat], average: Double?, period: RecapPeriod,
        midpoint: Date, end: Date, isOngoing: Bool
    ) -> RecapPersonality? {
        guard period.kind != .month, numeric.count >= 5 else { return nil }
        let values = numeric.compactMap(\.value)
        let ones = numeric.filter { $0.bucket == 1 }.count

        if let average, average <= 1.5, Double(ones) / Double(numeric.count) >= 0.5 { return .straightAs }

        let first = values.enumerated().filter { numeric[$0.offset].date < midpoint }.map(\.element)
        let second = values.enumerated().filter { numeric[$0.offset].date >= midpoint }.map(\.element)
        if first.count >= 3, second.count >= 3, let before = mean(first), let after = mean(second), before - after >= 0.4 {
            return .comeback
        }

        if let mean = mean(values) {
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            if variance.squareRoot() >= 1.0 { return .rollercoaster }
        }

        if !isOngoing {
            let lastStretch = end.addingTimeInterval(-end.timeIntervalSince(period.start) * 0.2)
            if Double(numeric.filter { $0.date >= lastStretch }.count) / Double(numeric.count) >= 0.4 { return .lastMinute }
        }

        if let best = subjects.first, let worst = subjects.last, worst.average - best.average >= 1.5 {
            return .specialty(subject: best.name)
        }
        return .steady
    }

    // MARK: - Absence

    private static func absence(for period: RecapPeriod, semesters: [RecapSemester],
                                lessons: [String: AbsenceDayLessons]?, end: Date) -> RecapAbsence? {
        let responses = semesters.compactMap(\.absence)
        guard !responses.isEmpty else { return nil }
        let days = responses.flatMap(\.absences).filter { day in
            MarkDateFormatter.date(from: day.date).map { $0 >= period.start && $0 < end } ?? false
        }
        let counts = AbsenceSummary.totalCounts(for: days)

        var top: (name: String, hours: Int)?
        if period.kind == .semester, let subjects = responses.first?.absencesPerSubject,
           let most = subjects.max(by: { $0.base < $1.base }), most.base > 0 {
            top = (most.subjectName.trimmingCharacters(in: .whitespacesAndNewlines), most.base)
        } else if let lessons {
            let dateKeys = Set(days.map { AbsenceOverrideProjection.dateKey($0.date) })
            let missed = lessons.filter { dateKeys.contains($0.key) }.values.flatMap(\.lessons).filter { !$0.isHidden }
            let bySubject = Dictionary(missed.map { ($0.subjectName, 1) }, uniquingKeysWith: +)
            if let most = bySubject.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) {
                top = (most.key, most.value)
            }
        }
        return RecapAbsence(counts: counts, topSubject: top?.name, topSubjectHours: top?.hours ?? 0)
    }

    // MARK: - Timetable

    private static func timetable(_ weeks: [TimetableWeek], from start: Date, to end: Date) -> RecapTimetable? {
        var seenDays: Set<String> = []
        var lessons = 0, canceled = 0, substitutions = 0
        var canceledBySubject: [String: Int] = [:]
        for week in weeks {
            for day in week.days where day.dayType == .workDay {
                guard let date = day.date, date >= start, date < end, seenDays.insert(day.id).inserted else { continue }
                for lesson in day.lessons where lesson.subjectName != nil || lesson.changeKind != .none {
                    lessons += 1
                    switch lesson.changeKind {
                    case .canceled:
                        canceled += 1
                        if let name = lesson.subjectName { canceledBySubject[name, default: 0] += 1 }
                    case .substitution:
                        substitutions += 1
                    case .none, .roomChanged, .added:
                        break
                    }
                }
            }
        }
        guard lessons > 0 else { return nil }
        let top = canceledBySubject.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
        return RecapTimetable(lessons: lessons, canceled: canceled, substitutions: substitutions, topCanceledSubject: top)
    }

    // MARK: - Report cards

    private static func reportCard(for period: RecapPeriod, semesters: [RecapSemester], terms: [ReportCardTerm]) -> RecapReportCard? {
        let semester = ReportCardPeriod(startYear: period.year, semester: period.number)
        let term = terms.first { $0.matches(semester) }
        if let term, term.isClosed, !term.marks.isEmpty {
            let values = term.marks.compactMap { GradeMath.parseMarkValue($0.markText) }
            guard let average = term.average ?? mean(values) else { return nil }
            return RecapReportCard(average: average, isEstimate: false,
                                   ones: term.marks.filter { $0.markText == "1" }.count, borderline: 0)
        }
        guard let subjects = semesters.first(where: { $0.period == semester })?.subjects, !subjects.isEmpty else { return nil }
        let prepared = Dictionary(subjects.map { ($0.id, GradeMath.prepare($0)) }, uniquingKeysWith: { first, _ in first })
        let estimates = ReportCardEstimate.estimates(subjects: subjects, prepared: prepared, written: term)
        guard let average = ReportCardEstimate.average(of: estimates) else { return nil }
        return RecapReportCard(average: average, isEstimate: true,
                               ones: estimates.filter { $0.markValue == 1 }.count,
                               borderline: estimates.filter { $0.borderline != nil }.count)
    }

    private static func lastYear(for period: RecapPeriod, input: RecapInput, end: Date) -> RecapLastYear? {
        let spring = ReportCardPeriod(startYear: period.year - 1, semester: 2)
        guard let term = input.reportCards.first(where: { $0.matches(spring) }), term.average != nil || term.absentHours != nil else {
            return nil
        }
        let autumnStart = RecapCalendar.date(period.year, 9, 1)
        let autumn = input.semesters.filter { $0.period == ReportCardPeriod(startYear: period.year, semester: 1) }
        let autumnDays = autumn.compactMap(\.absence).flatMap(\.absences).filter { day in
            MarkDateFormatter.date(from: day.date).map { $0 >= autumnStart && $0 < end } ?? false
        }
        return RecapLastYear(
            springTerm: ReportCardText.term(spring),
            springAverage: term.average,
            springAbsentHours: term.absentHours,
            autumnAverage: average(in: autumn, from: autumnStart, to: end),
            autumnAbsentHours: autumn.contains { $0.absence != nil } ? AbsenceSummary.totalCounts(for: autumnDays).total : nil
        )
    }
}
