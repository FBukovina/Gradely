import Foundation

enum AbsenceSubjectFallback {
    struct Term: Equatable {
        let start: Date
        let end: Date
        let weekStarts: [Date]
    }

    static func currentTerm(containing date: Date, calendar: Calendar = TimetableDates.weekCalendar) -> Term {
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

        let end = min(day, termEnd)
        return Term(start: start, end: end, weekStarts: weekStarts(from: start, through: end))
    }

    static func makeAbsences(
        from response: AbsenceResponse,
        timetableResponses: [TimetableResponse],
        subjects: [Subject],
        validDateRange: ClosedRange<Date>? = nil,
        calendar: Calendar = TimetableDates.weekCalendar
    ) -> [AbsencePerSubject] {
        guard response.absencesPerSubject.isEmpty else { return response.absencesPerSubject }
        guard !response.absences.isEmpty, !timetableResponses.isEmpty, !subjects.isEmpty else { return [] }

        let subjectIndex = SubjectIndex(subjects: subjects)
        var totals = Dictionary(
            uniqueKeysWithValues: subjects.map { ($0.id, SubjectAbsenceTotal(subject: $0)) }
        )
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
                    guard let matchedID = subjectIndex.match(rawTimetableID: subjectID, entity: timetableSubject) else {
                        continue
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

        guard assignedAnyFullDay else { return [] }

        return subjects.compactMap { subject in
            guard let total = totals[subject.id], total.lessonsCount > 0 else { return nil }
            return AbsencePerSubject(
                subjectName: total.displayName,
                lessonsCount: total.lessonsCount,
                base: total.base,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            )
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

    init(subject: Subject) {
        let name = subject.trimmedName
        if !name.isEmpty {
            displayName = name
        } else if !subject.trimmedAbbrev.isEmpty {
            displayName = subject.trimmedAbbrev
        } else {
            displayName = subject.id
        }
    }
}

private struct SubjectIndex {
    private let byRawID: [String: String]
    private let byNormalizedText: [String: String]

    init(subjects: [Subject]) {
        byRawID = Dictionary(subjects.map { ($0.id, $0.id) }, uniquingKeysWith: { first, _ in first })

        var textMatches: [String: String] = [:]
        for subject in subjects {
            for value in [subject.trimmedName, subject.trimmedAbbrev] {
                let key = Self.normalized(value)
                guard !key.isEmpty, textMatches[key] == nil else { continue }
                textMatches[key] = subject.id
            }
        }
        byNormalizedText = textMatches
    }

    func match(rawTimetableID: String, entity: TimetableEntity?) -> String? {
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

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension AbsenceDay {
    var fullDayAbsenceCount: Int {
        unsolved + ok + missed
    }
}
