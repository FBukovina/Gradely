import Foundation
import Testing
@testable import Gradely

struct GradeyTwoPointZeroTests {
    @Test func absenceRiskComputesMissesUntilThreshold() {
        let response = AbsenceResponse(
            percentageThreshold: 25,
            absences: [],
            absencesPerSubject: [
                AbsencePerSubject(
                    subjectName: "Matematika",
                    lessonsCount: 20,
                    base: 4,
                    late: 0,
                    soon: 0,
                    school: 0,
                    distanceTeaching: 0
                )
            ]
        )

        let summary = AbsenceRiskSummary.make(response: response, subjects: response.absencesPerSubject)
        let subject = summary.subjects[0]

        #expect(subject.level == .watch)
        #expect(subject.missesUntilLimit == 2)
    }

    @Test func absenceRiskTreatsExactThresholdAsOverLimit() {
        let response = AbsenceResponse(
            percentageThreshold: 25,
            absences: [],
            absencesPerSubject: [
                AbsencePerSubject(
                    subjectName: "Český jazyk",
                    lessonsCount: 20,
                    base: 5,
                    late: 0,
                    soon: 0,
                    school: 0,
                    distanceTeaching: 0
                )
            ]
        )

        let subject = AbsenceRiskSummary.make(response: response, subjects: response.absencesPerSubject).subjects[0]

        #expect(subject.level == .overLimit)
        #expect(subject.missesUntilLimit == 0)
    }

    @Test func absenceRiskDoesNotGuessMissingThreshold() {
        let response = AbsenceResponse(
            percentageThreshold: nil,
            absences: [],
            absencesPerSubject: [
                AbsencePerSubject(
                    subjectName: "Biologie",
                    lessonsCount: 10,
                    base: 3,
                    late: 0,
                    soon: 0,
                    school: 0,
                    distanceTeaching: 0
                )
            ]
        )

        let summary = AbsenceRiskSummary.make(response: response, subjects: response.absencesPerSubject)

        #expect(summary.isThresholdUnavailable)
        #expect(summary.subjects[0].level == .unavailable)
        #expect(summary.subjects[0].missesUntilLimit == nil)
    }

    @Test func scopedMarksCacheDoesNotBleedBetweenAccounts() throws {
        let cache = InMemoryMarksCache()
        let firstScope = SchoolDataScope(rawValue: "account-one")
        let secondScope = SchoolDataScope(rawValue: "account-two")
        let firstResponse = MarksResponse(subjects: [PreviewData.subjects[0]])
        let secondResponse = MarksResponse(subjects: [PreviewData.subjects[1]])

        try cache.save(firstResponse, scope: firstScope)
        #expect(try cache.load(scope: secondScope) == nil)

        try cache.save(secondResponse, scope: secondScope)
        #expect(try cache.load(scope: firstScope)?.marksResponse == firstResponse)
        #expect(try cache.load(scope: secondScope)?.marksResponse == secondResponse)
    }

    @Test func gradeHistoryBuildsImprovingAndWorseningTrends() {
        let trends = PreviewData.gradeHistoryResponse.trends
        let math = trends.first { $0.subjectID == "math" }
        let czech = trends.first { $0.subjectID == "czech" }

        // The fixture's math series runs 2.4 → 1.78, czech 1.6 → 2.0.
        #expect(math?.isImproving == true)
        #expect(abs((math?.averageDelta ?? 0) - (1.78 - 2.4)) < 0.0001)
        #expect(czech?.isWorsening == true)
        #expect(abs((czech?.averageDelta ?? 0) - (2.0 - 1.6)) < 0.0001)
    }
}
