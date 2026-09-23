import Foundation
import Testing
@testable import Gradely

@MainActor
struct SubjectDetailSimulationTests {
    @Test func sameSubjectRefreshPreservesScenarioAndRecomputesAllResults() throws {
        let model = makeModel(subject: subject(value: "3"))
        model.updateTheoreticalMark("1")
        model.addHypotheticalGrade(value: 2, weight: 2)
        model.targetAverageText = "2,40"
        let rowID = try #require(model.hypotheticalGrades.first?.id)
        #expect(model.theoreticalAverage == 2)
        let previousTimeline = model.averageTimeline
        model.updateSubject(subject(value: "5"))
        #expect(model.theoreticalMark == "1")
        #expect(model.theoreticalAverage == 3)
        #expect(model.hypotheticalGrades.first?.id == rowID)
        #expect(model.targetAverageText == "2,40")
        #expect(model.averageTimeline != previousTimeline)
        #expect(model.simulationResult?.estimatedAverage == 3)
    }

    @Test func differentSubjectResetsLocalScenarioAndTarget() {
        let model = makeModel(subject: subject(value: "3"))
        model.updateTheoreticalMark("1")
        model.addHypotheticalGrade()
        model.targetAverageText = "1.5"
        model.targetWeight = 4
        model.updateSubject(subject(value: "2", id: "physics"))
        #expect(model.theoreticalMark.isEmpty)
        #expect(model.hypotheticalGrades.isEmpty)
        #expect(model.targetAverageText == "2.49")
        #expect(model.targetWeight == 1)
    }

    @Test func scenarioRowsAreBoundedEditableAndRemovable() throws {
        let model = makeModel(subject: subject(value: "3"))
        for _ in 0..<15 { model.addHypotheticalGrade() }
        #expect(model.hypotheticalGrades.count == 10)
        let row = try #require(model.hypotheticalGrades.first)
        model.updateHypotheticalGrade(id: row.id, value: 2, weight: 4)
        #expect(model.hypotheticalGrades.first?.value == 2)
        #expect(model.hypotheticalGrades.first?.weight == 4)
        model.updateHypotheticalGrade(id: row.id, value: .nan, weight: 0)
        #expect(model.hypotheticalGrades.first?.value == 2)
        #expect(model.hypotheticalGrades.first?.weight == 4)
        model.removeHypotheticalGrade(id: row.id)
        #expect(model.hypotheticalGrades.count == 9)
    }

    @Test func localDifferenceDoesNotSubtractAnInconsistentOfficialAverage() {
        let model = makeModel(subject: subject(value: "3", official: "2,80"))
        model.updateTheoreticalMark("1")
        #expect(model.currentAverage == 2.8)
        #expect(model.theoreticalAverage == 2)
        #expect(model.theoreticalDifference == -1)
        #expect(model.calculationWarningKey == "detail.intelligence.averageMismatch")
    }

    @Test func fractionalWeightsStayLocalInsteadOfRoundingInProviderPayload() {
        let model = makeModel(subject: subject(value: "3", weight: 1.5, remote: true))
        model.updateTheoreticalMark("1")
        #expect(!model.isPredictingExactAverage)
        #expect(model.theoreticalAverage == 2.2)
    }

    @Test func staleProviderPredictionCannotReplaceNewSubjectRevision() async throws {
        let client = DeferredGradePredictionClient()
        let model = makeModel(subject: subject(value: "3", remote: true), client: client)
        model.updateTheoreticalMark("1")
        await client.waitForRequests(1)
        model.updateSubject(subject(value: "5", remote: true))
        await client.waitForRequests(2)
        #expect(client.pending.count == 2)
        guard client.pending.count == 2 else {
            client.pending.forEach { $0.resume(throwing: CancellationError()) }
            return
        }
        client.pending[1].resume(returning: subject(value: "5", official: "4.20"))
        for _ in 0..<30 where model.isPredictingExactAverage { await Task.yield() }
        client.pending[0].resume(returning: subject(value: "3", official: "1.10"))
        for _ in 0..<30 { await Task.yield() }
        #expect(model.theoreticalAverage == 4.2)
    }

    @Test func disablingProviderPredictionInvalidatesAnOtherwiseIdenticalBaseline() async throws {
        let client = DeferredGradePredictionClient()
        let model = makeModel(subject: subject(value: "3", remote: true), client: client)
        model.updateTheoreticalMark("1")
        await client.waitForRequests(1)
        let pending = try #require(client.pending.first)
        model.updateSubject(subject(value: "3", remote: false))
        pending.resume(returning: subject(value: "3", official: "1.10"))
        for _ in 0..<30 { await Task.yield() }
        #expect(!model.isPredictingExactAverage)
        #expect(model.theoreticalAverage == 2)
    }

    @Test func logoutRejectsAnOutstandingProviderPrediction() async throws {
        let client = DeferredGradePredictionClient()
        let session = StoredSession(accessToken: "access", refreshToken: "refresh", tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600), baseURL: URL(string: "https://school.example")!)
        let repository = SchoolRepository(client: client, sessionStore: InMemorySessionStore(session: session), marksCache: InMemoryMarksCache())
        let original = subject(value: "3", remote: true)
        let request = Task { try await repository.predictSubjectAverage(subject: original, markText: "1", weight: 1) }
        await client.waitForRequests(1)
        let pending = try #require(client.pending.first)
        try repository.logout()
        pending.resume(returning: subject(value: "3", official: "1.10"))
        do { _ = try await request.value; Issue.record("A prediction from the logged-out account was accepted") }
        catch { #expect(error is CancellationError) }
    }

    private func makeModel(subject: Subject, client: any BakalariClient = MockBakalariClient()) -> SubjectDetailViewModel {
        let session = StoredSession(
            accessToken: "grade-test-access", refreshToken: "grade-test-refresh", tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600), baseURL: URL(string: "https://school.example")!
        )
        return SubjectDetailViewModel(subject: subject, absence: nil, repository: SchoolRepository(
            client: client, sessionStore: InMemorySessionStore(session: session), marksCache: InMemoryMarksCache()
        ))
    }

    private func subject(value: String, id: String = "math", weight: Double = 1, official: String? = nil, remote: Bool = false) -> Subject {
        Subject(
            marks: [Mark(markDate: "2026-09-10T10:00:00+02:00", markText: value, type: "grade", weight: weight, subjectID: id, id: "grade")],
            subjectInfo: SubjectInfo(id: id, abbrev: id, name: id), averageText: official, markPredictionEnabled: remote
        )
    }
}

@MainActor
private final class DeferredGradePredictionClient: BakalariClient {
    var pending: [CheckedContinuation<Subject, Error>] = []
    private let base = MockBakalariClient()

    func waitForRequests(_ count: Int) async {
        for _ in 0..<100 {
            if pending.count >= count { return }
            await Task.yield()
        }
    }

    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse {
        try await base.login(baseURL: baseURL, username: username, password: password)
    }
    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse {
        try await base.refreshToken(baseURL: baseURL, refreshToken: refreshToken)
    }
    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse {
        try await base.fetchMarks(baseURL: baseURL, accessToken: accessToken)
    }
    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse {
        try await base.fetchAbsences(baseURL: baseURL, accessToken: accessToken)
    }
    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse {
        try await base.fetchUser(baseURL: baseURL, accessToken: accessToken)
    }
    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse {
        try await base.fetchTimetable(baseURL: baseURL, accessToken: accessToken, date: date)
    }
}
