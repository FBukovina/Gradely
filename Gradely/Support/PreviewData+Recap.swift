import Foundation

/// A full semester of demo marks and absence for Gradey Recap
/// (`-uiTestingRecapData`). Dates follow the demo clock, so the current
/// semester always has something in it.
extension PreviewData {
    struct RecapFixture {
        let marks: MarksResponse
        let absence: AbsenceResponse
        /// The semester before, but only within the same school year, the way
        /// a device that has had the app since September would have it.
        let archive: RecapArchive
    }

    static func recapFixture(now: Date) -> RecapFixture {
        let current = ReportCardPeriod(containing: now)
        var archive = RecapArchive()
        if current.semester == 2 {
            let previous = ReportCardPeriod(startYear: current.startYear, semester: 1)
            let bounds = recapBounds(previous)
            archive.marks[RecapArchive.key(for: previous)] = recapMarks(from: bounds.start, to: bounds.end, seed: 7)
            archive.absence[RecapArchive.key(for: previous)] = recapAbsence(from: bounds.start, to: bounds.end, seed: 7)
        }
        let start = recapBounds(current).start
        let end = min(recapBounds(current).end, now)
        return RecapFixture(
            marks: recapMarks(from: start, to: end, seed: 3),
            absence: recapAbsence(from: start, to: end, seed: 3),
            archive: archive
        )
    }

    private struct RecapDemoSubject {
        let id: String
        let abbrev: String
        let name: String
        /// Mark texts the generator cycles through; a later half lets one subject come back.
        let early: [String]
        let late: [String]
    }

    private static let recapDemoSubjects = [
        RecapDemoSubject(id: "math", abbrev: "M", name: "Matematika", early: ["1", "1-", "2", "1"], late: ["1", "2+", "1"]),
        RecapDemoSubject(id: "czech", abbrev: "ČJ", name: "Český jazyk", early: ["2", "1-", "2-", "2"], late: ["1", "2", "2+"]),
        RecapDemoSubject(id: "eng", abbrev: "AJ", name: "Anglický jazyk", early: ["1", "1", "1-", "1"], late: ["1", "1+", "2"]),
        RecapDemoSubject(id: "phys", abbrev: "F", name: "Fyzika", early: ["3", "4", "3-", "2"], late: ["3", "3+", "4"]),
        RecapDemoSubject(id: "hist", abbrev: "D", name: "Dějepis", early: ["4", "3", "4-", "3"], late: ["2", "1", "2+", "1-"]),
        RecapDemoSubject(id: "bio", abbrev: "Bi", name: "Biologie", early: ["2", "1", "2"], late: ["1", "2", "1"]),
        RecapDemoSubject(id: "pe", abbrev: "Tv", name: "Tělesná výchova", early: ["1", "N"], late: ["1", "1"])
    ]

    private static func recapBounds(_ semester: ReportCardPeriod) -> (start: Date, end: Date) {
        let period = RecapPeriod.semester(semester.semester, schoolYear: semester.startYear)
        return (period.start, period.end)
    }

    private static func recapMarks(from start: Date, to end: Date, seed: Int) -> MarksResponse {
        let span = max(end.timeIntervalSince(start), 86_400)
        let weights: [Double] = [1, 2, 3, 1, 5, 2]
        let subjects = recapDemoSubjects.enumerated().map { index, demo -> Subject in
            let texts = demo.early + demo.late
            var marks: [Mark] = []
            for (offset, text) in texts.enumerated() {
                // Spread evenly with a per-subject shift, early texts in the first half.
                let position = (Double(offset) + 0.5 + Double((index * 7 + seed) % 5) / 10) / Double(texts.count)
                guard let date = recapSchoolDay(start.addingTimeInterval(span * min(position, 0.98))), date < end else { continue }
                let weight = weights[(offset + index + seed) % weights.count]
                let isPoints = demo.id == "bio" && offset == 1
                marks.append(Mark(
                    markDate: recapISO(date, hour: 8 + (offset + index) % 6),
                    caption: weight >= 3 ? "Písemná práce" : (weight == 2 ? "Test" : "Ústní zkoušení"),
                    markText: isPoints ? "18" : text,
                    type: isPoints ? "points" : (weight >= 3 ? "written" : "oral"),
                    weight: isPoints ? nil : weight,
                    subjectID: demo.id,
                    isPoints: isPoints,
                    id: "recap-\(seed)-\(demo.id)-\(offset)",
                    pointsText: isPoints ? "18" : nil,
                    maxPoints: isPoints ? 20 : nil
                ))
            }
            return Subject(marks: marks, subjectInfo: SubjectInfo(id: demo.id, abbrev: demo.abbrev, name: demo.name),
                           averageText: nil, markPredictionEnabled: true)
        }
        return MarksResponse(subjects: subjects)
    }

    private static func recapAbsence(from start: Date, to end: Date, seed: Int) -> AbsenceResponse {
        let span = max(end.timeIntervalSince(start), 86_400)
        let pattern: [(ok: Int, unsolved: Int, late: Int)] = [(6, 0, 0), (2, 0, 0), (0, 0, 1), (6, 0, 0), (0, 2, 0), (1, 0, 0), (0, 0, 1), (6, 0, 0), (3, 0, 0), (0, 1, 0)]
        let days = pattern.enumerated().compactMap { offset, counts -> AbsenceDay? in
            let position = (Double(offset) + 0.3 + Double(seed % 3) / 10) / Double(pattern.count)
            guard let date = recapSchoolDay(start.addingTimeInterval(span * position)), date < end else { return nil }
            return AbsenceDay(date: recapISO(RecapCalendar.calendar.startOfDay(for: date), hour: 0),
                              unsolved: counts.unsolved, ok: counts.ok, missed: 0, late: counts.late,
                              soon: 0, school: 0, distanceTeaching: 0)
        }
        let perSubject = [
            AbsencePerSubject(subjectName: "Fyzika", lessonsCount: 40, base: 6, late: 1, soon: 0, school: 0, distanceTeaching: 0),
            AbsencePerSubject(subjectName: "Matematika", lessonsCount: 70, base: 5, late: 0, soon: 0, school: 0, distanceTeaching: 0),
            AbsencePerSubject(subjectName: "Dějepis", lessonsCount: 30, base: 3, late: 0, soon: 0, school: 0, distanceTeaching: 0)
        ]
        return AbsenceResponse(percentageThreshold: 25, absences: days, absencesPerSubject: perSubject)
    }

    /// Moves Saturdays and Sundays to the next Monday.
    private static func recapSchoolDay(_ date: Date) -> Date? {
        let calendar = RecapCalendar.calendar
        switch calendar.component(.weekday, from: date) {
        case 7: return calendar.date(byAdding: .day, value: 2, to: date)
        case 1: return calendar.date(byAdding: .day, value: 1, to: date)
        default: return date
        }
    }

    private static func recapISO(_ date: Date, hour: Int) -> String {
        let calendar = RecapCalendar.calendar
        let day = calendar.startOfDay(for: date)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = Homework.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: calendar.date(byAdding: .hour, value: hour, to: day) ?? day)
    }
}
