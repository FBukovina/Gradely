import Foundation
import Testing
@testable import Gradely

@MainActor
struct SchoolSnapshotStoreTests {
    @Test func failedManualRefreshPreservesOfflineMarks() async throws {
        let client = SuspendedSchoolClient()
        let cache = InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date(timeIntervalSince1970: 42)))
        let repository = makeRepository(client, cache: cache)
        let request = Task { try await repository.loadMarks(forceRefresh: true) }
        await waitUntil { client.marksCalls == 1 }
        client.finishMarks(.failure(URLError(.notConnectedToInternet)))
        _ = try? await request.value
        #expect(try repository.loadCachedMarks()?.marksResponse == PreviewData.marksResponse)
        #expect(try repository.loadCachedMarks()?.cachedAt == Date(timeIntervalSince1970: 42))
    }

    @Test func logoutDuringMarksCannotRepopulateCache() async throws {
        let client = SuspendedSchoolClient(), cache = InMemoryMarksCache()
        let repository = makeRepository(client, cache: cache)
        let request = Task { try await repository.loadMarks() }
        await waitUntil { client.marksCalls == 1 }
        try repository.logout()
        client.finishMarks(.success(PreviewData.marksResponse))
        do { _ = try await request.value; Issue.record("Old request was accepted after logout") }
        catch { #expect(error is CancellationError) }
        #expect(try cache.load() == nil)
        #expect(try repository.currentStoredSession() == nil)
    }

    @Test func logoutDuringTokenRefreshCannotRestoreSession() async throws {
        let client = SuspendedSchoolClient()
        client.suspendsToken = true
        let repository = makeRepository(client, expired: true)
        let request = Task { try await repository.validSession() }
        await waitUntil { client.refreshCalls == 1 }
        try repository.logout()
        client.finishToken()
        do { _ = try await request.value; Issue.record("Old token was persisted after logout") }
        catch { #expect(error is CancellationError) }
        #expect(try repository.currentStoredSession() == nil)
    }

    @Test func sharedConsumersJoinOneRequestAndKeepCachedContent() async throws {
        let client = SuspendedSchoolClient()
        let cache = InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: .distantPast))
        let repository = makeRepository(client, cache: cache)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SchoolSnapshotStore(repository: repository, historyDirectory: directory)
        store.activateCurrentScope()
        #expect(store.subjects == PreviewData.subjects)
        let first = Task { await store.refresh(requirements: .marks, force: true) }
        await waitUntil { client.marksCalls == 1 }
        let second = Task { await store.refresh(requirements: .marks, force: true) }
        await Task.yield()
        first.cancel() // One consumer leaving must not cancel the shared request.
        client.finishMarks(.success(PreviewData.marksResponse))
        await first.value; await second.value
        #expect(client.marksCalls == 1)
        #expect(store.subjects == PreviewData.subjects)
        #expect(store.marksFetchedAt != .distantPast)
        await store.refresh(requirements: .marks)
        #expect(client.marksCalls == 1)
    }

    @Test func scopeChangeRejectsOldSnapshotPublication() async throws {
        let client = SuspendedSchoolClient(), repository = makeRepository(SuspendedSchoolClient())
        let active = makeRepository(client)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SchoolSnapshotStore(repository: active, historyDirectory: directory)
        let task = Task { await store.refresh(requirements: .marks, force: true) }
        await waitUntil { client.marksCalls == 1 }
        try active.logout()
        store.activateCurrentScope()
        client.finishMarks(.success(PreviewData.marksResponse))
        await task.value
        #expect(store.scope == nil)
        #expect(store.subjects.isEmpty)
        #expect(store.marksFetchedAt == nil)
        _ = repository
    }

    @Test func sourceFailuresDoNotAdvanceLastSuccess() async throws {
        let client = SuspendedSchoolClient()
        let date = Date(timeIntervalSince1970: 42)
        let repository = makeRepository(client, cache: InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: date)))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SchoolSnapshotStore(repository: repository, historyDirectory: directory)
        let task = Task { await store.refresh(requirements: .marks, force: true) }
        await waitUntil { client.marksCalls == 1 }
        client.finishMarks(.failure(URLError(.timedOut)))
        await task.value
        #expect(store.marksFetchedAt == date)
        #expect(store.sourceState("marks").error != nil)
        #expect(!store.subjects.isEmpty)
    }

    @Test func directDashboardAndSharedConsumerCoalesceProviderMarks() async throws {
        let client = SuspendedSchoolClient()
        let repository = makeRepository(client)
        let marks = Task { try await repository.loadMarks() }
        await waitUntil { client.marksCalls == 1 }
        let dashboard = Task { try await repository.loadDashboard() }
        await Task.yield()
        client.finishMarks(.success(PreviewData.marksResponse))
        _ = try await marks.value
        _ = try await dashboard.value
        #expect(client.marksCalls == 1)
    }

    @Test func clearingCacheInvalidatesPendingProviderWrites() async throws {
        let client = SuspendedSchoolClient(), cache = InMemoryMarksCache()
        let repository = makeRepository(client, cache: cache)
        let task = Task { try await repository.loadMarks() }
        await waitUntil { client.marksCalls == 1 }
        try repository.clearLocalCaches()
        client.finishMarks(.success(PreviewData.marksResponse))
        do { _ = try await task.value; Issue.record("A cleared cache was repopulated by an older request") }
        catch { #expect(error is CancellationError) }
        let cached = try cache.load()
        #expect(cached == nil)
    }

    @Test func sharedAbsenceAndUserFetchUserOnlyOnceAndDoNotInventHistoryFreshness() async {
        let client = SuspendedSchoolClient()
        let repository = makeRepository(client)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SchoolSnapshotStore(repository: repository, historyDirectory: directory)
        await store.refresh(requirements: [.absence, .user, .history], force: true)
        #expect(client.userCalls == 1)
        #expect(store.user != nil)
        #expect(store.absence != nil)
        #expect(store.sourceState("history").lastSuccessAt == nil)
    }

    @Test func cachedTimetablePublicationPreservesItsOriginalTimestamp() throws {
        let now = Date(), old = Date(timeIntervalSince1970: 42)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let widget = NextLessonWidgetStore(fileURL: directory.appending(path: "widget.json"))
        let timetable = InMemoryTimetableCache(cached: CachedTimetable(response: PreviewData.timetableResponse,
            weekStart: TimetableDates.monday(of: now), cachedAt: old))
        var session = PreviewData.expiredSession
        session.expiresAt = .distantFuture
        let repository = SchoolRepository(client: SuspendedSchoolClient(), sessionStore: InMemorySessionStore(session: session),
            marksCache: InMemoryMarksCache(), timetableCache: timetable, nextLessonWidgetStore: widget, dateProvider: { now })
        _ = repository.loadCachedTimetable(weekContaining: now)
        let snapshot = try widget.loadSnapshot()
        #expect(snapshot?.cachedAt == old)
    }

    @Test func canceledTimetableWaiterLeavesOtherConsumerRunning() async throws {
        let client = SuspendedSchoolClient()
        client.suspendsTimetable = true
        let repository = makeRepository(client)
        let first = Task { try await repository.loadTimetable(weekContaining: Date()) }
        await waitUntil { client.timetableCalls == 1 }
        let second = Task { try await repository.loadTimetable(weekContaining: Date()) }
        await Task.yield()
        first.cancel()
        do { _ = try await first.value; Issue.record("Canceled waiter should return immediately") }
        catch { #expect(error is CancellationError) }
        #expect(client.timetableCalls == 1)
        client.finishTimetable()
        _ = try await second.value
        #expect(client.timetableCalls == 1)
    }

    @Test func eduPageHistoryWithoutChildIdentityIsNeitherLoadedFromCacheNorFetched() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = StoredSession(accessToken: "session", refreshToken: "", tokenType: "Cookie", expiresAt: .distantFuture,
            baseURL: URL(string: "https://school.edupage.org")!, provider: .eduPage, linkedAccountID: "parent-account")
        let repository = SchoolRepository(client: MockBakalariClient(), sessionStore: InMemorySessionStore(session: session),
            marksCache: InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date())))
        struct Cache: Encodable { let response: GradeHistoryResponse; let fetchedAt: Date }
        let cacheURL = directory.appending(path: SchoolDataScope(session: session).filename(prefix: "grade-history-cache"))
        try JSONEncoder.sessionEncoder.encode(Cache(response: PreviewData.gradeHistoryResponse, fetchedAt: Date())).write(to: cacheURL)
        let client = HistoryReadCounter()
        let store = SchoolSnapshotStore(repository: repository,
            historyRepository: GradeyHistoryRepository(client: client, authClient: MockGradeyAuthClient()), historyDirectory: directory)
        store.activateCurrentScope()
        #expect(store.history.events.isEmpty)
        #expect(!store.preparedCalculations.isEmpty)
        await store.refresh(requirements: .history, force: true)
        #expect(client.calls == 0)
        #expect(store.history.events.isEmpty)
        #expect(store.sourceState("history").lastSuccessAt == nil)
        #expect(!store.sourceState("history").isRefreshing)
    }

    private func makeRepository(_ client: SuspendedSchoolClient, cache: InMemoryMarksCache = InMemoryMarksCache(), expired: Bool = false) -> SchoolRepository {
        var session = PreviewData.expiredSession
        session.expiresAt = expired ? .distantPast : .distantFuture
        return SchoolRepository(client: client, sessionStore: InMemorySessionStore(session: session), marksCache: cache)
    }
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() }
        #expect(condition())
    }
}

private final class HistoryReadCounter: GradeyHistoryClient {
    var calls = 0
    func loadGradeHistory(linkedAccountID: String?, days: Int?, gradeySession: GradeyAuthSession) async throws -> GradeHistoryResponse {
        calls += 1
        return PreviewData.gradeHistoryResponse
    }
}

private final class SuspendedSchoolClient: BakalariClient {
    var marksCalls = 0, refreshCalls = 0, userCalls = 0, timetableCalls = 0
    var suspendsToken = false
    var suspendsTimetable = false
    private var marksContinuation: CheckedContinuation<MarksResponse, Error>?
    private var tokenContinuation: CheckedContinuation<LoginResponse, Error>?
    private var timetableContinuation: CheckedContinuation<TimetableResponse, Error>?
    func finishMarks(_ result: Result<MarksResponse, Error>) { marksContinuation?.resume(with: result); marksContinuation = nil }
    func finishToken() { tokenContinuation?.resume(returning: RefreshSpyBakalariClient.defaultResponse); tokenContinuation = nil }
    func finishTimetable() { timetableContinuation?.resume(returning: PreviewData.timetableResponse); timetableContinuation = nil }
    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse { RefreshSpyBakalariClient.defaultResponse }
    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse {
        refreshCalls += 1
        if suspendsToken { return try await withCheckedThrowingContinuation { tokenContinuation = $0 } }
        return RefreshSpyBakalariClient.defaultResponse
    }
    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse {
        marksCalls += 1
        return try await withCheckedThrowingContinuation { marksContinuation = $0 }
    }
    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse { PreviewData.absenceResponse }
    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse { userCalls += 1; return PreviewData.userResponse }
    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse {
        timetableCalls += 1
        if suspendsTimetable { return try await withCheckedThrowingContinuation { timetableContinuation = $0 } }
        return PreviewData.timetableResponse
    }
    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject { subject }
}
