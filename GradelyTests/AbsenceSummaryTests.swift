import Foundation
import Testing
@testable import Gradely

struct AbsenceSummaryTests {
    @Test func decodesAbsenceResponseWithDailyRows() throws {
        let json = """
        {
          "PercentageThreshold": 25,
          "Absences": [
            {
              "Date": "2026-02-10T00:00:00+01:00",
              "Unsolved": 1,
              "Ok": 2,
              "Missed": 3,
              "Late": 4,
              "Soon": 5,
              "School": 6,
              "DistanceTeaching": 7
            }
          ],
          "AbsencesPerSubject": []
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(AbsenceResponse.self, from: data)

        #expect(response.percentageThreshold == 25)
        #expect(response.absences.count == 1)
        #expect(response.absences[0].ok == 2)
        #expect(response.absencesPerSubject.isEmpty)
    }

    @Test func totalCountsSumEveryDailyField() {
        let total = AbsenceSummary.totalCounts(for: [
            absenceDay("2026-02-10T00:00:00+01:00", unsolved: 1, ok: 2, missed: 3, late: 4, soon: 5, school: 6, distanceTeaching: 7),
            absenceDay("2026-02-11T00:00:00+01:00", unsolved: 2, ok: 3, missed: 4, late: 5, soon: 6, school: 7, distanceTeaching: 8)
        ])

        #expect(total == AbsenceCounts(
            unsolved: 3,
            ok: 5,
            missed: 7,
            late: 9,
            soon: 11,
            school: 13,
            distanceTeaching: 15
        ))
    }

    @Test func monthSummariesGroupDailyAbsenceByMonth() {
        let rows = AbsenceSummary.monthSummaries(for: [
            absenceDay("2026-02-10T00:00:00+01:00", ok: 2),
            absenceDay("2026-02-12T00:00:00+01:00", ok: 3),
            absenceDay("2026-03-01T00:00:00+01:00", unsolved: 1)
        ])

        #expect(rows.count == 2)
        #expect(rows[0].counts.ok == 5)
        #expect(rows[1].counts.unsolved == 1)
    }

    @Test func subjectSummariesHighlightThresholdAndSortHighestFirst() {
        let rows = AbsenceSummary.subjectSummaries(
            for: [
                AbsencePerSubject(subjectName: "Matematika", lessonsCount: 40, base: 4, late: 0, soon: 0, school: 0, distanceTeaching: 0),
                AbsencePerSubject(subjectName: "Český jazyk", lessonsCount: 10, base: 3, late: 0, soon: 0, school: 0, distanceTeaching: 0)
            ],
            threshold: 25
        )

        #expect(rows.first?.subjectName == "Český jazyk")
        #expect(rows.first?.exceedsThreshold == true)
        #expect(rows.last?.exceedsThreshold == false)
    }

    @Test func dashboardUsesOfficialSubjectAbsenceWithoutTimetableFallback() async throws {
        let absence = AbsenceResponse(
            percentageThreshold: 25,
            absences: [absenceDay("2026-02-10T00:00:00+01:00", ok: 2)],
            absencesPerSubject: []
        )
        let repository = SchoolRepository(
            client: MockBakalariClient(absenceResult: absence),
            sessionStore: InMemorySessionStore(session: validSession()),
            marksCache: InMemoryMarksCache()
        )

        let dashboard = try await repository.loadDashboard()

        #expect(dashboard.absencesPerSubject.isEmpty)
    }

    private func absenceDay(
        _ date: String,
        unsolved: Int = 0,
        ok: Int = 0,
        missed: Int = 0,
        late: Int = 0,
        soon: Int = 0,
        school: Int = 0,
        distanceTeaching: Int = 0
    ) -> AbsenceDay {
        AbsenceDay(
            date: date,
            unsolved: unsolved,
            ok: ok,
            missed: missed,
            late: late,
            soon: soon,
            school: school,
            distanceTeaching: distanceTeaching
        )
    }

    private func validSession() -> StoredSession {
        StoredSession(
            accessToken: "mock-access",
            refreshToken: "mock-refresh",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600),
            baseURL: URL(string: "https://demo.bakalari.cz/")!
        )
    }
}
