import Foundation
import Testing
@testable import Gradely

struct AverageTimelineTests {
    @Test func entriesBuildRunningWeightedAverageInDateOrder() {
        let subject = Subject(
            marks: [
                Mark(
                    markDate: "2026-05-10T10:00:00+02:00",
                    caption: "Test B",
                    theme: nil,
                    markText: "3",
                    type: "written",
                    typeNote: nil,
                    weight: 1,
                    subjectID: "math",
                    id: "mark-b"
                ),
                Mark(
                    markDate: "2026-05-01T10:00:00+02:00",
                    caption: "Test A",
                    theme: nil,
                    markText: "1",
                    type: "written",
                    typeNote: nil,
                    weight: 2,
                    subjectID: "math",
                    id: "mark-a"
                )
            ],
            subjectInfo: SubjectInfo(id: "math", abbrev: "M", name: "Matematika"),
            averageText: nil
        )

        let entries = AverageTimeline.entries(for: subject)

        #expect(entries.count == 2)
        #expect(entries.map(\.markID) == ["mark-a", "mark-b"])
        #expect(entries[0].runningAverage == 1.0)
        #expect(abs(entries[1].runningAverage - (1.0 * 2 + 3.0 * 1) / 3.0) < 0.0001)
        #expect(entries[0].weight == 2)
        #expect(entries[1].weight == 1)
        #expect(entries[0].date < entries[1].date)
    }

    @Test func entriesExcludePointsAndUnsupportedMarks() {
        let subject = Subject(
            marks: [
                Mark(
                    markDate: "2026-05-03T10:00:00+02:00",
                    caption: "Body",
                    theme: nil,
                    markText: "8",
                    type: "points",
                    typeNote: nil,
                    weight: nil,
                    subjectID: "math",
                    isPoints: true,
                    id: "points-mark",
                    pointsText: "8",
                    maxPoints: 10
                ),
                Mark(
                    markDate: "2026-05-04T10:00:00+02:00",
                    caption: "Slovní hodnocení",
                    theme: nil,
                    markText: "A",
                    type: "unsupported",
                    typeNote: nil,
                    weight: nil,
                    subjectID: "math",
                    id: "unsupported-mark"
                ),
                Mark(
                    markDate: "2026-05-05T10:00:00+02:00",
                    caption: "Písemka",
                    theme: nil,
                    markText: "2",
                    type: "written",
                    typeNote: nil,
                    weight: 1,
                    subjectID: "math",
                    id: "graded-mark"
                )
            ],
            subjectInfo: SubjectInfo(id: "math", abbrev: "M", name: "Matematika"),
            averageText: nil
        )

        let entries = AverageTimeline.entries(for: subject)

        #expect(entries.map(\.markID) == ["graded-mark"])
        #expect(entries[0].markValue == 2.0)
    }

    @Test func entriesEmptyForPointsOnlySubject() {
        #expect(AverageTimeline.entries(for: PreviewData.pointsOnlySubject).isEmpty)
    }

    @Test func riskFactoryNormalizesFractionalThreshold() {
        let absence = AbsencePerSubject(
            subjectName: "Matematika",
            lessonsCount: 20,
            base: 4,
            late: 0,
            soon: 0,
            school: 0,
            distanceTeaching: 0
        )
        let summary = AbsenceSubjectSummary(absence: absence, threshold: 0.25, stableID: "subject-0-matematika")

        let risk = AbsenceRiskSubject.make(summary: summary, threshold: 0.25)

        #expect(risk.threshold == 25)
        #expect(risk.level == .watch)
        #expect(risk.missesUntilLimit == 2)
        #expect(summary.exceedsThreshold == false)
    }

    @Test func riskFactoryLevelBoundaries() {
        func risk(base: Int, lessons: Int, threshold: Double?) -> AbsenceRiskSubject {
            let absence = AbsencePerSubject(
                subjectName: "Subject",
                lessonsCount: lessons,
                base: base,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            )
            let summary = AbsenceSubjectSummary(absence: absence, threshold: threshold, stableID: "subject-0-subject")
            return AbsenceRiskSubject.make(summary: summary, threshold: threshold)
        }

        // 22.5 % of a 25 % limit is a 0.9 ratio — the high band starts here.
        #expect(risk(base: 9, lessons: 40, threshold: 25).level == .high)

        let over = risk(base: 5, lessons: 20, threshold: 25)
        #expect(over.level == .overLimit)
        #expect(over.missesUntilLimit == 0)

        let unavailable = risk(base: 5, lessons: 20, threshold: nil)
        #expect(unavailable.level == .unavailable)
        #expect(unavailable.threshold == nil)
        #expect(unavailable.missesUntilLimit == nil)
    }
}
