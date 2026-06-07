import Foundation

enum AbsenceSubjectFallback {
    struct Result: Equatable {
        let absences: [AbsencePerSubject]
        let stableIDHints: [String]

        static let empty = Result(absences: [], stableIDHints: [])
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
        let dates = absences.compactMap { MarkDateFormatter.date(from: $0.date) }
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
        validDateRange: ClosedRange<Date>? = nil,
        calendar: Calendar = TimetableDates.weekCalendar
    ) -> Result {
        guard response.absencesPerSubject.isEmpty else {
            return Result(absences: response.absencesPerSubject, stableIDHints: [])
        }
        guard !response.absences.isEmpty, !timetableResponses.isEmpty else { return .empty }

        var subjectCatalog = TimetableSubjectCatalog(markSubjects: subjects)
        var totals: [String: SubjectAbsenceTotal] = [:]

        let absenceByDate = Dictionary(
            response.absences.compactMap { day -> (String, AbsenceDay)? in
                guard let key = dateKey(day.date) else { return nil }
                return (key, day)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var assignedAnyFullDay = false

        for timetable in timetableResponses {
            let timetableSubjects = Dictionary(
                timetable.subjects.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for day in timetable.days {
                guard
                    let date = MarkDateFormatter.date(from: day.date),
                    isDate(date, inside: validDateRange, calendar: calendar)
                else {
                    continue
                }

                let countableAtoms = day.atoms.filter { atom in
                    atom.subjectID != nil && !LessonChangeKind(changeType: atom.change?.changeType).isCanceled
                }
                guard !countableAtoms.isEmpty else { continue }

                var matchedSubjectIDs: [String] = []
                for atom in countableAtoms {
                    guard let subjectID = atom.subjectID else { continue }
                    let timetableSubject = timetableSubjects[subjectID]
                    let matchedID = subjectCatalog.key(rawTimetableID: subjectID, entity: timetableSubject)

                    if totals[matchedID] == nil {
                        totals[matchedID] = SubjectAbsenceTotal(
                            displayName: subjectCatalog.displayName(for: matchedID)
                        )
                    }

                    totals[matchedID]?.lessonsCount += 1
                    matchedSubjectIDs.append(matchedID)
                }

                guard
                    let absenceDay = absenceByDate[TimetableDates.apiDateString(date)],
                    absenceDay.fullDayAbsenceCount >= countableAtoms.count
                else {
                    continue
                }

                for subjectID in matchedSubjectIDs {
                    totals[subjectID]?.base += 1
                    assignedAnyFullDay = true
                }
            }
        }

        guard assignedAnyFullDay else { return .empty }

        let rows: [(absence: AbsencePerSubject, stableIDHint: String)] = subjectCatalog.keys.compactMap { key in
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
            stableIDHints: rows.map(\.stableIDHint)
        )
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
        if let date = MarkDateFormatter.date(from: string) {
            return TimetableDates.apiDateString(date)
        }

        let fallback = String(string.split(separator: "T").first ?? "")
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

private struct TimetableSubjectCatalog {
    private(set) var keys: [String] = []
    private var candidatesByKey: [String: SubjectCandidate] = [:]
    private let markIndex: MarkSubjectIndex

    init(markSubjects: [Subject]) {
        markIndex = MarkSubjectIndex(subjects: markSubjects)
    }

    mutating func key(rawTimetableID: String, entity: TimetableEntity?) -> String {
        let key = Self.stableKey(rawTimetableID: rawTimetableID, entity: entity)
        guard candidatesByKey[key] == nil else {
            return key
        }

        let candidate = SubjectCandidate(
            key: key,
            displayName: displayName(rawTimetableID: rawTimetableID, entity: entity)
        )
        candidatesByKey[key] = candidate
        keys.append(key)
        return key
    }

    func displayName(for key: String) -> String {
        candidatesByKey[key]?.displayName ?? "Subject"
    }

    private func displayName(rawTimetableID: String, entity: TimetableEntity?) -> String {
        if let markSubject = markIndex.match(rawTimetableID: rawTimetableID, entity: entity) {
            return markSubject.displayName
        }

        if let name = entity?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        if let abbrev = entity?.abbrev.trimmingCharacters(in: .whitespacesAndNewlines), !abbrev.isEmpty {
            return abbrev
        }

        let rawID = rawTimetableID.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawID.isEmpty ? "Subject" : rawID
    }

    private static func stableKey(rawTimetableID: String, entity: TimetableEntity?) -> String {
        let rawID = rawTimetableID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawID.isEmpty {
            return "raw-\(Self.normalized(rawID))"
        }

        if let entity {
            for value in [entity.name, entity.abbrev] {
                let key = Self.normalized(value)
                if !key.isEmpty { return "text-\(key)" }
            }
        }

        return "raw-blank"
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct MarkSubjectIndex {
    private let byRawID: [String: MarkSubjectCandidate]
    private let byNormalizedText: [String: MarkSubjectCandidate]

    init(subjects: [Subject]) {
        var rawMatches: [String: MarkSubjectCandidate] = [:]
        var textMatches: [String: MarkSubjectCandidate] = [:]

        for (index, subject) in subjects.enumerated() {
            let candidate = MarkSubjectCandidate(
                rawID: subject.id,
                name: subject.trimmedName,
                abbrev: subject.trimmedAbbrev,
                displayName: Self.displayName(for: subject, fallback: "Subject \(index + 1)")
            )

            let rawID = subject.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawID.isEmpty, rawMatches[subject.id] == nil {
                rawMatches[subject.id] = candidate
            }

            for value in [candidate.name, candidate.abbrev] {
                let key = Self.normalized(value)
                guard !key.isEmpty, textMatches[key] == nil else { continue }
                textMatches[key] = candidate
            }
        }

        byRawID = rawMatches
        byNormalizedText = textMatches
    }

    func match(rawTimetableID: String, entity: TimetableEntity?) -> MarkSubjectCandidate? {
        if let match = byRawID[rawTimetableID] {
            return match
        }

        if let entity {
            for value in [entity.name, entity.abbrev] {
                let key = Self.normalized(value)
                if let match = byNormalizedText[key] {
                    return match
                }
            }
        }

        let key = Self.normalized(rawTimetableID)
        return byNormalizedText[key]
    }

    private static func displayName(for subject: Subject, fallback: String) -> String {
        if !subject.trimmedName.isEmpty {
            return subject.trimmedName
        }

        if !subject.trimmedAbbrev.isEmpty {
            return subject.trimmedAbbrev
        }

        let rawID = subject.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawID.isEmpty ? fallback : rawID
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct SubjectCandidate {
    let key: String
    let displayName: String
}

private struct MarkSubjectCandidate {
    let rawID: String
    let name: String
    let abbrev: String
    let displayName: String
}

private extension AbsenceDay {
    var fullDayAbsenceCount: Int {
        unsolved + ok + missed
    }
}
