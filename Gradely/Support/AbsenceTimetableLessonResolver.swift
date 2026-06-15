import Foundation

struct AbsenceTimetableLessonResolver {
    private var subjectCatalog: AbsenceTimetableSubjectCatalog

    init(subjects: [Subject]) {
        subjectCatalog = AbsenceTimetableSubjectCatalog(markSubjects: subjects)
    }

    var subjectKeys: [String] {
        subjectCatalog.keys
    }

    mutating func countableLessons(
        for day: TimetableDayDTO,
        in timetable: TimetableResponse,
        dateKey: String
    ) -> [AbsenceCountableTimetableLesson] {
        let timetableSubjectsByID = Dictionary(
            timetable.subjects.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let hoursByID = Dictionary(
            timetable.hours.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var lessons: [AbsenceCountableTimetableLesson] = []
        var seenLessonKeys: Set<String> = []

        for atom in day.atoms {
            guard !LessonChangeKind(changeType: atom.change?.changeType).isCanceled else { continue }
            guard let subjectReference = Self.effectiveSubjectReference(for: atom) else { continue }

            let entity = Self.timetableSubject(
                for: subjectReference,
                timetableSubjects: timetable.subjects,
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
                AbsenceCountableTimetableLesson(
                    id: Self.lessonID(dateKey: dateKey, hourID: atom.hourID, subjectKey: subjectKey),
                    dateKey: dateKey,
                    hourID: atom.hourID,
                    hourCaption: hour.caption.isEmpty ? "\(atom.hourID)" : hour.caption,
                    timeRange: Self.timeRange(for: hour),
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

    static func candidates(
        on date: Date,
        in timetable: TimetableResponse,
        subjects: [Subject],
        calendar: Calendar = TimetableDates.weekCalendar
    ) -> [AbsenceLessonCandidate] {
        guard let day = timetable.days.first(where: { day in
            guard let dayDate = MarkDateFormatter.date(from: day.date) else { return false }
            return calendar.isDate(dayDate, inSameDayAs: date)
        }) else {
            return []
        }

        var resolver = AbsenceTimetableLessonResolver(subjects: subjects)
        let dateKey = TimetableDates.apiDateString(calendar.startOfDay(for: date))
        return resolver.countableLessons(
            for: day,
            in: timetable,
            dateKey: dateKey
        )
        .map(\.candidate)
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

    static func storageSafe(_ value: String) -> String {
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

    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func lessonID(dateKey: String, hourID: Int, subjectKey: String) -> String {
        "lesson-\(dateKey)-\(hourID)-\(storageSafe(subjectKey))"
    }

    private static func timeRange(for hour: TimetableHour) -> String {
        let begin = hour.beginTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = hour.endTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !begin.isEmpty, !end.isEmpty else { return "" }
        return "\(begin)-\(end)"
    }
}

struct AbsenceCountableTimetableLesson {
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

private struct AbsenceTimetableSubjectCatalog {
    private(set) var keys: [String] = []
    private var candidatesByKey: [String: AbsenceSubjectCandidate] = [:]
    private let markIndex: AbsenceMarkSubjectIndex

    init(markSubjects: [Subject]) {
        markIndex = AbsenceMarkSubjectIndex(subjects: markSubjects)
    }

    mutating func key(rawTimetableID: String, entity: TimetableEntity?) -> String {
        let key = Self.stableKey(rawTimetableID: rawTimetableID, entity: entity)
        guard candidatesByKey[key] == nil else {
            return key
        }

        let candidate = AbsenceSubjectCandidate(
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
            return "raw-\(AbsenceTimetableLessonResolver.normalized(rawID))"
        }

        if let entity {
            for value in [entity.name, entity.abbrev] {
                let key = AbsenceTimetableLessonResolver.normalized(value)
                if !key.isEmpty { return "text-\(key)" }
            }
        }

        return "raw-blank"
    }
}

private struct AbsenceMarkSubjectIndex {
    private let byRawID: [String: AbsenceMarkSubjectCandidate]
    private let byNormalizedText: [String: AbsenceMarkSubjectCandidate]

    init(subjects: [Subject]) {
        var rawMatches: [String: AbsenceMarkSubjectCandidate] = [:]
        var textMatches: [String: AbsenceMarkSubjectCandidate] = [:]

        for (index, subject) in subjects.enumerated() {
            let candidate = AbsenceMarkSubjectCandidate(
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
                let key = AbsenceTimetableLessonResolver.normalized(value)
                guard !key.isEmpty, textMatches[key] == nil else { continue }
                textMatches[key] = candidate
            }
        }

        byRawID = rawMatches
        byNormalizedText = textMatches
    }

    func match(rawTimetableID: String, entity: TimetableEntity?) -> AbsenceMarkSubjectCandidate? {
        if let match = byRawID[rawTimetableID] {
            return match
        }

        if let entity {
            for value in [entity.name, entity.abbrev] {
                let key = AbsenceTimetableLessonResolver.normalized(value)
                if let match = byNormalizedText[key] {
                    return match
                }
            }
        }

        let key = AbsenceTimetableLessonResolver.normalized(rawTimetableID)
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
}

private struct AbsenceSubjectCandidate {
    let key: String
    let displayName: String
}

private struct AbsenceMarkSubjectCandidate {
    let rawID: String
    let name: String
    let abbrev: String
    let displayName: String
}
