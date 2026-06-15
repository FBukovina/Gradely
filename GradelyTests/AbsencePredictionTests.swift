import Foundation
import Testing
@testable import Gradely

@MainActor
struct AbsencePredictionTests {
    @Test func projectionAddsExcusedHoursAndUpdatesSubjectPercentages() {
        let subjectRows = AbsenceSummary.subjectSummaries(
            for: [
                AbsencePerSubject(
                    subjectName: "Matematika",
                    lessonsCount: 20,
                    base: 4,
                    late: 0,
                    soon: 0,
                    school: 0,
                    distanceTeaching: 0
                )
            ],
            threshold: 25,
            stableIDHints: ["raw-math"]
        )
        let result = AbsencePrediction.project(
            currentTotalCounts: AbsenceCounts(
                unsolved: 0,
                ok: 3,
                missed: 1,
                late: 0,
                soon: 0,
                school: 0,
                distanceTeaching: 0
            ),
            subjectRows: subjectRows,
            selectedLessons: [
                Self.lesson("lesson-2026-06-15-1-raw-math", subjectKey: "raw-math", subjectName: "Matematika", hourID: 1),
                Self.lesson("lesson-2026-06-15-2-raw-math", subjectKey: "raw-math", subjectName: "Matematika", hourID: 2),
                Self.lesson("lesson-2026-06-15-2-raw-math", subjectKey: "raw-math", subjectName: "Matematika", hourID: 2)
            ],
            threshold: 25
        )

        #expect(result.addedHours == 2)
        #expect(result.projectedTotal.ok == 5)
        #expect(result.projectedTotal.total == 6)
        let row = try? #require(result.subjectRows.first)
        #expect(row?.currentBase == 4)
        #expect(row?.projectedBase == 6)
        #expect(row?.currentLessonsCount == 20)
        #expect(row?.projectedLessonsCount == 22)
        #expect(row?.crossesThreshold == true)
        #expect(row?.exceedsThreshold == true)
    }

    @Test func projectionShowsUnknownBaselineWithoutInventingPercentage() {
        let result = AbsencePrediction.project(
            currentTotalCounts: .zero,
            subjectRows: [],
            selectedLessons: [
                Self.lesson("lesson-2026-06-15-1-raw-bio", subjectKey: "raw-bio", subjectName: "Biologie", hourID: 1)
            ],
            threshold: 25
        )

        let row = try? #require(result.subjectRows.first)
        #expect(result.addedHours == 1)
        #expect(result.projectedTotal.ok == 1)
        #expect(row?.hasBaseline == false)
        #expect(row?.projectedPercentage == nil)
    }

    @Test func repositoryLoadsPredictionLessonsFromCachedTimetableFirst() async throws {
        let date = try #require(TimetableDates.weekCalendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let weekStart = TimetableDates.monday(of: date)
        let cache = InMemoryTimetableCache()
        try cache.save(
            MockBakalariClient.rebased(PreviewData.timetableResponse, toWeekContaining: date),
            weekStart: weekStart
        )
        let client = CachedPredictionClient()
        let repository = BakalariRepository(
            client: client,
            sessionStore: InMemorySessionStore(session: Self.validSession()),
            marksCache: InMemoryMarksCache(),
            timetableCache: cache
        )

        let lessons = try await repository.loadAbsencePredictionLessons(on: date, user: nil as UserResponse?)

        #expect(!lessons.isEmpty)
        #expect(client.timetableFetchCount == 0)
    }

    @Test func viewModelCommitsCancelsAndClearsPredictionSelections() async throws {
        let today = try #require(TimetableDates.weekCalendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let viewModel = AbsenceViewModel(
            repository: BakalariRepository(
                client: MockBakalariClient(),
                sessionStore: InMemorySessionStore(session: Self.validSession()),
                marksCache: InMemoryMarksCache()
            ),
            today: today
        )

        viewModel.openPredictionSheet()
        await viewModel.loadPredictionLessonsForSelectedDate()
        let firstLesson = try #require(viewModel.predictionLessons.first)
        viewModel.togglePredictionLesson(firstLesson)
        viewModel.cancelPredictionSheet()
        #expect(viewModel.predictionSelectedLessons.isEmpty)

        viewModel.openPredictionSheet()
        await viewModel.loadPredictionLessonsForSelectedDate()
        viewModel.togglePredictionLesson(firstLesson)
        viewModel.commitPredictionSelections()
        #expect(viewModel.predictionSelectedLessons.count == 1)
        #expect(viewModel.predictionResult.addedHours == 1)

        viewModel.clearPredictionSelections()
        #expect(viewModel.predictionSelectedLessons.isEmpty)
        #expect(viewModel.predictionResult.addedHours == 0)
    }

    private static func lesson(
        _ id: String,
        subjectKey: String,
        subjectName: String,
        hourID: Int
    ) -> AbsenceLessonCandidate {
        AbsenceLessonCandidate(
            id: id,
            dateKey: "2026-06-15",
            hourID: hourID,
            hourCaption: "\(hourID)",
            timeRange: "8:00-8:45",
            subjectKey: subjectKey,
            subjectName: subjectName
        )
    }

    private static func validSession() -> StoredSession {
        StoredSession(
            accessToken: "mock-access",
            refreshToken: "mock-refresh",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600),
            baseURL: URL(string: "https://demo.bakalari.cz/")!
        )
    }
}

private final class CachedPredictionClient: BakalariClient {
    var timetableFetchCount = 0

    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse {
        LoginResponse(
            accessToken: "mock-access",
            refreshToken: "mock-refresh",
            tokenType: "Bearer",
            expiresIn: 3600,
            apiVersion: nil,
            appVersion: nil,
            userID: "mock-user"
        )
    }

    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse {
        try await login(baseURL: baseURL, username: "", password: "")
    }

    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse {
        PreviewData.marksResponse
    }

    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse {
        PreviewData.absenceResponse
    }

    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse {
        PreviewData.userResponse
    }

    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse {
        timetableFetchCount += 1
        throw BakalariAPIError.httpStatus(500, nil)
    }

    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject {
        subject
    }
}
