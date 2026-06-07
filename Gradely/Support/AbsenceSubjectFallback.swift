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
        manualSelections: AbsenceLessonSelections = .empty,
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

        var subjectCatalog = TimetableSubjectCatalog(markSubjects: subjects)
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
            let timetableSubjects = Dictionary(
                timetable.subjects.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let hoursByID = Dictionary(
                timetable.hours.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for day in timetable.days {
                guard
                    let date = MarkDateFormatter.date(from: day.date),
                    isDate(date, inside: validDateRange, calendar: calendar)
                else {
                    continue
                }

                let dateKey = TimetableDates.apiDateString(date)
                let countableLessons = countableLessons(
                    for: day,
                    dateKey: dateKey,
                    timetableSubjects: timetable.subjects,
                    timetableSubjectsByID: timetableSubjects,
                    hoursByID: hoursByID,
                    subjectCatalog: &subjectCatalog
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

        let unresolvedDays = unresolvedPartialDays.values.sorted { $0.dateKey < $1.dateKey }
        guard assignedAnyFullDay || !unresolvedDays.isEmpty else { return .empty }

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
            stableIDHints: rows.map(\.stableIDHint),
            unresolvedPartialDays: unresolvedDays,
            appliedManualSelectionCount: appliedManualSelectionCount
        )
    }

    private static func countableLessons(
        for day: TimetableDayDTO,
        dateKey: String,
        timetableSubjects: [TimetableEntity],
        timetableSubjectsByID: [String: TimetableEntity],
        hoursByID: [Int: TimetableHour],
        subjectCatalog: inout TimetableSubjectCatalog
    ) -> [CountableTimetableLesson] {
        var lessons: [CountableTimetableLesson] = []
        var seenLessonKeys: Set<String> = []

        for atom in day.atoms {
            guard !LessonChangeKind(changeType: atom.change?.changeType).isCanceled else { continue }
            guard let subjectReference = effectiveSubjectReference(for: atom) else { continue }

            let entity = timetableSubject(
                for: subjectReference,
                timetableSubjects: timetableSubjects,
                timetableSubjectsByID: timetableSubjectsByID
            )
            let rawID = entity?.id ?? subjectReference
            let subjectKey = subjectCatalog.key(rawTimetableID: rawID, entity: entity)
            let dedupeKey = "\(atom.hourID)#\(subjectKey)"
            guard seenLessonKeys.insert(dedupeKey).inserted else { continue }

            let hour = hoursByID[atom.hourID]
                ?? TimetableHour(id: atom.hourID, caption: "\(atom.hourID)", beginTime: "", endTime: "")
            let subjectName = subjectCatalog.displayName(for: subjectKey)
            lessons.append(
                CountableTimetableLesson(
                    id: lessonID(dateKey: dateKey, hourID: atom.hourID, subjectKey: subjectKey),
                    dateKey: dateKey,
                    hourID: atom.hourID,
                    hourCaption: hour.caption.isEmpty ? "\(atom.hourID)" : hour.caption,
                    timeRange: timeRange(for: hour),
                    subjectKey: subjectKey,
                    subjectName: subjectName
                )
            )
        }

        return lessons.sorted { lhs, rhs in
            if lhs.hourID != rhs.hourID {
                return lhs.hourID < rhs.hourID
            }
            return lhs.subjectName.localizedCaseInsensitiveCompare(rhs.subjectName) == .orderedAscending
        }
    }

    private static func effectiveSubjectReference(for atom: TimetableAtom) -> String? {
        let changeSubject = atom.change?.changeSubject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !changeSubject.isEmpty {
            return changeSubject
        }

        guard let subjectID = atom.subjectID else { return nil }
        return subjectID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func timetableSubject(
        for subjectReference: String,
        timetableSubjects: [TimetableEntity],
        timetableSubjectsByID: [String: TimetableEntity]
    ) -> TimetableEntity? {
        if let entity = timetableSubjectsByID[subjectReference] {
            return entity
        }

        let normalizedReference = normalized(subjectReference)
        return timetableSubjects.first { entity in
            [
                entity.id,
                entity.abbrev,
                entity.name
            ].contains { normalized($0) == normalizedReference }
        }
    }

    private static func lessonID(dateKey: String, hourID: Int, subjectKey: String) -> String {
        "lesson-\(dateKey)-\(hourID)-\(storageSafe(subjectKey))"
    }

    private static func storageSafe(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0).lowercased() : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")

        return normalized.isEmpty ? "unknown" : String(normalized.prefix(80))
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func timeRange(for hour: TimetableHour) -> String {
        let begin = hour.beginTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = hour.endTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !begin.isEmpty, !end.isEmpty else { return "" }
        return "\(begin)-\(end)"
    }

    private static func dayTitle(for date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.defaultDigits)
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

private struct CountableTimetableLesson {
    let id: String
    let dateKey: String
    let hourID: Int
    let hourCaption: String
    let timeRange: String
    let subjectKey: String
    let subjectName: String

    var candidate: AbsenceLessonCandidate {
        AbsenceLessonCandidate(
            id: id,
            dateKey: dateKey,
            hourID: hourID,
            hourCaption: hourCaption,
            timeRange: timeRange,
            subjectKey: subjectKey,
            subjectName: subjectName
        )
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
