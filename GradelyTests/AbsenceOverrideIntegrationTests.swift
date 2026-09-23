import Foundation
import Testing
@testable import Gradely

@MainActor
struct AbsenceOverrideIntegrationTests {
    private let day = AbsenceDay(date: "2026-09-21T00:00:00+02:00", unsolved: 0, ok: 2, missed: 0,
                                 late: 0, soon: 0, school: 0, distanceTeaching: 0)
    private var raw: AbsenceResponse {
        AbsenceResponse(percentageThreshold: 25, absences: [day], absencesPerSubject: [
            AbsencePerSubject(subjectName: "Matematika", lessonsCount: 10, base: 2, late: 0, soon: 0, school: 0, distanceTeaching: 0)
        ])
    }
    private func session(username: String = "student", expired: Bool = false) -> StoredSession {
        StoredSession(accessToken: "token", refreshToken: "refresh", tokenType: "Bearer",
            expiresAt: expired ? .distantPast : .distantFuture, baseURL: URL(string: "https://school.example/")!,
            bakalari: BakalariCredentials(username: username, password: "password"))
    }
    private func edit(_ context: AbsenceOverrideEditorContext) -> AbsenceDayOverride {
        let rows = (0..<context.rawDay.ok).map { index in
            AbsenceOverrideAllocation(id: "unit-\(index)", subjectName: "Matematika", category: .ok)
        }
        return AbsenceDayOverride(scope: context.overrideScope, dateKey: context.dateKey, baselineDay: context.rawDay,
            allocations: rows, hiddenAllocationIDs: [rows[0].id])
    }
    private func repository(sessionStore: InMemorySessionStore, cache: InMemoryAbsenceCache,
                            overrides: any AbsenceOverrideStoring, response: AbsenceResponse? = nil) -> SchoolRepository {
        SchoolRepository(client: MockBakalariClient(absenceResult: response ?? raw, timetableError: URLError(.notConnectedToInternet)),
            sessionStore: sessionStore, marksCache: InMemoryMarksCache(), absenceCache: cache, absenceOverrideStore: overrides)
    }

    @Test func offlineEditPreservesRawCacheAndFreshnessAndSurvivesRestart() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let cache = InMemoryAbsenceCache(cachedAbsence: CachedAbsence(response: raw, cachedAt: fetchedAt))
        let sessions = InMemorySessionStore(session: session(expired: true))
        let overrides = InMemoryAbsenceOverrideStore()
        let repository = repository(sessionStore: sessions, cache: cache, overrides: overrides)
        let snapshot = SchoolSnapshotStore(repository: repository)
        snapshot.activateCurrentScope()
        let context = try await repository.loadAbsenceOverrideEditorContext(dateKey: "2026-09-21", user: nil)
        let result = try await repository.saveAbsenceOverride(edit(context), context: context, user: nil)
        #expect(result.response.absences[0].ok == 1)
        #expect(result.absencesPerSubject[0].base == 1)
        #expect(result.absencesPerSubject[0].lessonsCount == 10)
        #expect(result.absencesPerSubject[0].absencePercentage == 10)
        #expect(result.rawResponse == raw)
        #expect(try repository.loadCachedAbsence()?.response == raw)
        #expect(snapshot.absence?.response == result.response)
        #expect(snapshot.sourceState("absence").lastSuccessAt == fetchedAt)

        let restarted = self.repository(sessionStore: sessions, cache: cache, overrides: overrides)
        let cached = try #require(try restarted.loadCachedAbsenceData())
        #expect(cached.data.response.absences[0].ok == 1)
        #expect(cached.data.overrideMetadata.hiddenCount == 1)
        #expect(cached.cachedAt == fetchedAt)
        let refreshed = try await restarted.loadAbsence()
        #expect(refreshed.response.absences[0].ok == 1)
        #expect(refreshed.absencesPerSubject[0].base == 1)
    }

    @Test func accountSwitchRejectsOldEditorAndKeepsSameSchoolStudentsSeparate() async throws {
        let first = session(username: "student-one"), second = session(username: "student-two")
        #expect(SchoolDataScope.absenceOverrides(session: first) != SchoolDataScope.absenceOverrides(session: second))
        #expect(SchoolDataScope(session: first) == SchoolDataScope(session: second))
        let sessions = InMemorySessionStore(session: first)
        let cache = InMemoryAbsenceCache(cachedAbsence: CachedAbsence(response: raw, cachedAt: Date()))
        let overrides = InMemoryAbsenceOverrideStore()
        let repository = repository(sessionStore: sessions, cache: cache, overrides: overrides)
        let context = try await repository.loadAbsenceOverrideEditorContext(dateKey: "2026-09-21", user: nil)
        _ = try await repository.saveAbsenceOverride(edit(context), context: context, user: nil)
        try sessions.save(session: second)
        await #expect(throws: CancellationError.self) {
            _ = try await repository.saveAbsenceOverride(edit(context), context: context, user: nil)
        }
        #expect(try repository.loadCachedAbsenceData()?.data.overrideMetadata.hiddenCount == 0)
        try sessions.save(session: first)
        #expect(try repository.loadCachedAbsenceData()?.data.overrideMetadata.hiddenCount == 1)
    }

    @Test func logoutAndCacheClearDoNotDeleteUserEdits() async throws {
        let active = session()
        let sessions = InMemorySessionStore(session: active)
        let cache = InMemoryAbsenceCache(cachedAbsence: CachedAbsence(response: raw, cachedAt: Date()))
        let overrides = InMemoryAbsenceOverrideStore()
        let repository = repository(sessionStore: sessions, cache: cache, overrides: overrides)
        let context = try await repository.loadAbsenceOverrideEditorContext(dateKey: "2026-09-21", user: nil)
        _ = try await repository.saveAbsenceOverride(edit(context), context: context, user: nil)
        try repository.clearLocalCaches()
        #expect(try overrides.load(scope: SchoolDataScope.absenceOverrides(session: active)).count == 1)
        try repository.logout()
        #expect(try overrides.load(scope: SchoolDataScope.absenceOverrides(session: active)).count == 1)
        try sessions.save(session: active)
        let refreshed = try await repository.loadAbsence()
        #expect(refreshed.response.absences[0].ok == 1)
    }

    @Test func changedSchoolDayPausesPersistentlyAndRestoreUsesLatestRaw() async throws {
        let sessions = InMemorySessionStore(session: session())
        let cache = InMemoryAbsenceCache(cachedAbsence: CachedAbsence(response: raw, cachedAt: Date()))
        let overrides = InMemoryAbsenceOverrideStore()
        let repository = repository(sessionStore: sessions, cache: cache, overrides: overrides)
        let context = try await repository.loadAbsenceOverrideEditorContext(dateKey: "2026-09-21", user: nil)
        _ = try await repository.saveAbsenceOverride(edit(context), context: context, user: nil)
        let changedDay = AbsenceDay(date: day.date, unsolved: 1, ok: 1, missed: 0, late: 0, soon: 0, school: 0, distanceTeaching: 0)
        let changed = AbsenceResponse(percentageThreshold: 25, absences: [changedDay], absencesPerSubject: raw.absencesPerSubject)
        try cache.save(changed, scope: context.scope)
        let paused = try #require(try repository.loadCachedAbsenceData()).data
        #expect(paused.response == changed)
        #expect(paused.overrideMetadata.reviewOverrides.first?.pauseReason == .dayChanged)
        #expect(try overrides.load(scope: context.overrideScope).first?.pauseReason == .dayChanged)
        try cache.save(raw, scope: context.scope)
        #expect(try repository.loadCachedAbsenceData()?.data.overrideMetadata.reviewOverrides.count == 1)
        try cache.save(changed, scope: context.scope)
        let restored = try await repository.restoreAbsenceOverride(dateKey: context.dateKey, scope: context.scope, overrideScope: context.overrideScope,
            sessionGeneration: context.sessionGeneration, user: nil)
        #expect(restored.response == changed)
        #expect(restored.overrideMetadata == .empty)
    }

    @Test func directNetworkRefreshPublishesPausedEditsAndNewFreshness() async throws {
        let initialDate = Date(timeIntervalSince1970: 100)
        let refreshedDate = Date(timeIntervalSince1970: 200)
        let changedDay = AbsenceDay(date: day.date, unsolved: 1, ok: 1, missed: 0, late: 0, soon: 0, school: 0, distanceTeaching: 0)
        let changed = AbsenceResponse(percentageThreshold: 25, absences: [changedDay], absencesPerSubject: raw.absencesPerSubject)
        let cache = InMemoryAbsenceCache(cachedAbsence: CachedAbsence(response: raw, cachedAt: initialDate))
        let repository = SchoolRepository(
            client: MockBakalariClient(absenceResult: changed, timetableError: URLError(.notConnectedToInternet)),
            sessionStore: InMemorySessionStore(session: session()), marksCache: InMemoryMarksCache(),
            absenceCache: cache, absenceOverrideStore: InMemoryAbsenceOverrideStore(), dateProvider: { refreshedDate })
        let snapshot = SchoolSnapshotStore(repository: repository)
        snapshot.activateCurrentScope()
        let context = try await repository.loadAbsenceOverrideEditorContext(dateKey: "2026-09-21", user: nil)
        _ = try await repository.saveAbsenceOverride(edit(context), context: context, user: nil)
        #expect(snapshot.absence?.absencesPerSubject[0].base == 1)
        #expect(snapshot.sourceState("absence").lastSuccessAt == initialDate)
        _ = try await repository.loadAbsence(includeUser: false)
        #expect(snapshot.absence?.response == changed)
        #expect(snapshot.absence?.absencesPerSubject[0].base == 2)
        #expect(snapshot.absence?.overrideMetadata.reviewOverrides.first?.pauseReason == .dayChanged)
        #expect(snapshot.sourceState("absence").lastSuccessAt == refreshedDate)
    }

    @Test func linkedEduPageChildrenHaveIsolatedOverridesAndRejectStaleMutations() async throws {
        let firstChild = SchoolStudentProfile(id: "child-1", fullName: "First", classID: nil, className: nil)
        let secondChild = SchoolStudentProfile(id: "child-2", fullName: "Second", classID: nil, className: nil)
        var firstSession = session()
        firstSession.provider = .eduPage
        firstSession.bakalari = nil
        firstSession.linkedAccountID = "same-parent-login"
        firstSession.eduPage = EduPageSessionData(sessionID: "session", username: "parent", password: "password",
            gsecHash: "hash", userID: "parent", schoolName: nil, activeStudent: firstChild,
            linkedStudents: [firstChild, secondChild], subjects: [])
        var secondSession = firstSession
        secondSession.eduPage?.activeStudent = secondChild
        let firstScope = SchoolDataScope(session: firstSession), secondScope = SchoolDataScope(session: secondSession)
        #expect(firstScope != secondScope)
        let sessions = InMemorySessionStore(session: firstSession)
        let cache = InMemoryAbsenceCache(cachedAbsence: CachedAbsence(response: raw, cachedAt: Date()))
        let timetables = InMemoryTimetableCache()
        let week = TimetableDates.monday(of: MarkDateFormatter.date(from: "2026-09-21")!)
        try timetables.save(TimetableResponse(), weekStart: week, scope: firstScope)
        try timetables.save(TimetableResponse(), weekStart: week, scope: secondScope)
        let overrides = InMemoryAbsenceOverrideStore()
        let repository = SchoolRepository(client: MockBakalariClient(), sessionStore: sessions,
            marksCache: InMemoryMarksCache(), absenceCache: cache, timetableCache: timetables, absenceOverrideStore: overrides)
        let context = try await repository.loadAbsenceOverrideEditorContext(dateKey: "2026-09-21", user: nil)
        _ = try await repository.saveAbsenceOverride(edit(context), context: context, user: nil)
        try sessions.save(session: secondSession)
        #expect(try repository.loadCachedAbsenceData()?.data.overrideMetadata.hiddenCount == 0)
        await #expect(throws: CancellationError.self) {
            _ = try await repository.restoreAbsenceOverride(dateKey: context.dateKey, scope: context.scope, overrideScope: context.overrideScope,
                sessionGeneration: context.sessionGeneration, user: nil)
        }
        #expect(try overrides.load(scope: firstScope).count == 1)
        #expect(try overrides.load(scope: secondScope).isEmpty)
        try sessions.save(session: firstSession)
        #expect(try repository.loadCachedAbsenceData()?.data.overrideMetadata.hiddenCount == 1)
    }

    @Test func failedPersistenceDoesNotPublishOrAcknowledgeAnEdit() async throws {
        let sessions = InMemorySessionStore(session: session())
        let cache = InMemoryAbsenceCache(cachedAbsence: CachedAbsence(response: raw, cachedAt: Date()))
        let overrides = FailingAbsenceOverrideStore()
        let repository = repository(sessionStore: sessions, cache: cache, overrides: overrides)
        let context = try await repository.loadAbsenceOverrideEditorContext(dateKey: "2026-09-21", user: nil)
        var publishCount = 0
        repository.onAbsenceOverridesChange = { _, _ in publishCount += 1 }
        overrides.failWrites = true
        await #expect(throws: AbsenceOverrideStoreError.self) {
            _ = try await repository.saveAbsenceOverride(edit(context), context: context, user: nil)
        }
        #expect(publishCount == 0)
        #expect(try repository.loadCachedAbsenceData()?.data.response == raw)
        #expect(try overrides.load(scope: context.overrideScope).isEmpty)
    }

    @Test func editDuringInFlightFetchIsAppliedToCompletedResponse() async throws {
        let sessions = InMemorySessionStore(session: session())
        let cache = InMemoryAbsenceCache(cachedAbsence: CachedAbsence(response: raw, cachedAt: Date()))
        let client = DeferredAbsenceClient(response: raw)
        let repository = SchoolRepository(client: client, sessionStore: sessions, marksCache: InMemoryMarksCache(),
            absenceCache: cache, absenceOverrideStore: InMemoryAbsenceOverrideStore())
        let context = try await repository.loadAbsenceOverrideEditorContext(dateKey: "2026-09-21", user: nil)
        let refresh = Task { try await repository.loadAbsence(includeUser: false) }
        for _ in 0..<1_000 where client.continuation == nil { await Task.yield() }
        #expect(client.continuation != nil)
        _ = try await repository.saveAbsenceOverride(edit(context), context: context, user: nil)
        client.complete()
        let result = try await refresh.value
        #expect(result.response.absences[0].ok == 1)
        #expect(result.absencesPerSubject[0].base == 1)
        #expect(try repository.loadCachedAbsence()?.response == raw)
    }
}

@MainActor
private final class FailingAbsenceOverrideStore: AbsenceOverrideStoring {
    var failWrites = false
    private let backing = InMemoryAbsenceOverrideStore()
    func load(scope: SchoolDataScope) throws -> [AbsenceDayOverride] { try backing.load(scope: scope) }
    func save(_ overrides: [AbsenceDayOverride], scope: SchoolDataScope) throws {
        if failWrites { throw AbsenceOverrideStoreError.unavailable }
        try backing.save(overrides, scope: scope)
    }
    func clear(scope: SchoolDataScope) throws { try backing.clear(scope: scope) }
    func clearAll() throws { try backing.clearAll() }
}

@MainActor
private final class DeferredAbsenceClient: BakalariClient {
    let response: AbsenceResponse
    var continuation: CheckedContinuation<AbsenceResponse, Never>?
    let mock = MockBakalariClient(timetableError: URLError(.notConnectedToInternet))
    init(response: AbsenceResponse) { self.response = response }
    func complete() { continuation?.resume(returning: response); continuation = nil }
    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse { try await mock.login(baseURL: baseURL, username: username, password: password) }
    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse { try await mock.refreshToken(baseURL: baseURL, refreshToken: refreshToken) }
    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse { try await mock.fetchMarks(baseURL: baseURL, accessToken: accessToken) }
    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse { await withCheckedContinuation { continuation = $0 } }
    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse { try await mock.fetchUser(baseURL: baseURL, accessToken: accessToken) }
    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse { throw URLError(.notConnectedToInternet) }
    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject { subject }
}
