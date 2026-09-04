import Foundation
import Testing
@testable import Gradely

@MainActor
struct PermanentTimetableTests {
    private var monday: Date { TimetableDates.monday(of: Date()) }

    private var permanent: TimetableResponse {
        TimetableResponse(
            hours: [TimetableHour(id: 1, caption: "1", beginTime: "8:00", endTime: "8:45")],
            days: [TimetableDayDTO(
                atoms: [TimetableAtom(hourID: 1, subjectID: "P", cycleIDs: ["odd"])],
                dayOfWeek: 1, date: "2020-03-09T00:00:00+01:00",
                dayDescription: "Old holiday", dayType: "Holiday"
            )],
            subjects: [TimetableEntity(id: "P", abbrev: "P", name: "Permanent lesson")],
            cycles: [
                TimetableEntity(id: "odd", abbrev: "L", name: "Odd weeks"),
                TimetableEntity(id: "even", abbrev: "S", name: "Even weeks")
            ]
        )
    }

    @Test func permanentMappingIgnoresDatesAndHolidayMetadataButKeepsCycles() throws {
        let week = TimetableMapper.makeWeek(from: permanent, weekStart: monday, kind: .permanent)
        let day = try #require(week.days.first)
        #expect(day.date == nil)
        #expect(!day.isToday)
        #expect(day.id == "dow-1")
        #expect(day.dayType == .workDay)
        #expect(day.dayDescription.isEmpty)
        #expect(day.lessons.first?.subjectName == "Permanent lesson")
        #expect(day.lessons.first?.cycles == ["Odd weeks"])
    }

    @Test(arguments: [false, true])
    func cachesKeepKindsAndAccountsSeparateAndPermanentSurvivesWeekChange(onDisk: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache: any TimetableCaching = onDisk
            ? try TimetableCache(directory: directory)
            : InMemoryTimetableCache()
        let first = SchoolDataScope(rawValue: "first")
        let second = SchoolDataScope(rawValue: "second")
        let weekly = PreviewData.timetableResponse
        try cache.save(weekly, weekStart: monday, scope: first)
        try cache.save(permanent, weekStart: monday, scope: first, kind: .permanent)
        #expect(try cache.load(weekStart: monday, scope: first)?.response == weekly)
        #expect(try cache.load(weekStart: monday, scope: first, kind: .permanent)?.response == permanent)
        #expect(try cache.load(weekStart: monday, scope: second, kind: .permanent) == nil)
        let next = TimetableDates.addingWeeks(1, to: monday)
        #expect(try cache.load(weekStart: next, scope: first, kind: .permanent)?.response == permanent)
        #expect(try cache.load(weekStart: next, scope: first) == nil)
        if onDisk {
            let reopened = try TimetableCache(directory: directory)
            #expect(try reopened.load(weekStart: next, scope: first, kind: .permanent)?.response == permanent)
        }
        try cache.clear(scope: first)
        #expect(try cache.load(weekStart: monday, scope: first) == nil)
        #expect(try cache.load(weekStart: monday, scope: first, kind: .permanent) == nil)
    }

    @Test func switchingBackRestoresWeeklyDatesAndAnchor() async throws {
        let repository = repository(client: MockBakalariClient(permanentTimetableResult: permanent))
        let model = TimetableViewModel(repository: repository)
        await model.loadIfNeeded()
        #expect(model.kind == .weekly)
        await model.goToNextWeek()
        let anchor = model.weekAnchor
        await model.selectKind(.permanent)
        #expect(model.kind == .permanent)
        #expect(model.selectedDay?.lessons.first?.subjectName == "Permanent lesson")
        #expect(model.todaySummary == nil)
        #expect(model.days.allSatisfy { $0.date == nil && !$0.isToday })
        await model.goToNextWeek()
        await model.goToToday()
        #expect(model.weekAnchor == anchor)
        await model.selectKind(.weekly)
        #expect(model.weekAnchor == anchor)
        #expect(model.days.allSatisfy { $0.date != nil })
        #expect(model.days.flatMap(\.lessons).contains { $0.isCanceled })
    }

    @Test func offlinePermanentUsesItsOwnCache() async throws {
        let cache = InMemoryTimetableCache()
        let online = repository(client: MockBakalariClient(permanentTimetableResult: permanent), cache: cache)
        _ = try await online.loadTimetable(weekContaining: monday)
        _ = try await online.loadTimetable(weekContaining: monday, kind: .permanent)
        let offline = repository(client: MockBakalariClient(timetableError: URLError(.notConnectedToInternet)), cache: cache)
        let model = TimetableViewModel(repository: offline)
        await model.selectKind(.permanent)
        #expect(model.selectedDay?.lessons.first?.subjectName == "Permanent lesson")
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading && !model.isRefreshing)
    }

    @Test func permanentFailureNeverDisplaysWeeklyLessons() async throws {
        let cache = InMemoryTimetableCache()
        let online = repository(client: MockBakalariClient(), cache: cache)
        _ = try await online.loadTimetable(weekContaining: monday)
        let offline = repository(client: MockBakalariClient(timetableError: URLError(.notConnectedToInternet)), cache: cache)
        let model = TimetableViewModel(repository: offline)
        await model.loadIfNeeded()
        #expect(!model.days.isEmpty)
        await model.selectKind(.permanent)
        #expect(model.week == nil)
        #expect(model.errorMessage != nil)
        await model.selectKind(.weekly)
        #expect(!model.days.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func lateWeeklyResponseCannotReplacePermanentSelection() async throws {
        let client = DelayedWeeklyTimetableClient(permanent: permanent)
        let model = TimetableViewModel(repository: repository(client: client))
        let weeklyLoad = Task { await model.refresh() }
        await client.waitForWeeklyRequest()
        await model.selectKind(.permanent)
        client.completeWeeklyRequest()
        await weeklyLoad.value
        #expect(model.kind == .permanent)
        #expect(model.selectedDay?.lessons.first?.subjectName == "Permanent lesson")
        #expect(model.days.allSatisfy { $0.date == nil })
        #expect(!model.isLoading && !model.isRefreshing)
    }

    @Test func permanentRequestsUseTheirOwnEndpointWithoutADate() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TimetableEndpointURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = URLSessionBakalariClient(urlSession: session)
        let baseURL = URL(string: "https://school.example")!
        _ = try await client.fetchTimetable(baseURL: baseURL, accessToken: "test-token", date: monday)
        let weekly = try #require(TimetableEndpointURLProtocol.lastRequest)
        #expect(weekly.url?.path == "/api/3/timetable/actual")
        #expect(weekly.url?.query == "date=\(TimetableDates.apiDateString(monday))")
        _ = try await client.fetchPermanentTimetable(baseURL: baseURL, accessToken: "test-token")
        let permanent = try #require(TimetableEndpointURLProtocol.lastRequest)
        #expect(permanent.url?.path == "/api/3/timetable/permanent")
        #expect(permanent.url?.query == nil)
        #expect(permanent.httpMethod == "GET")
        #expect(permanent.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test func permanentLoadsDoNotReplaceTheNextLessonWidget() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NextLessonWidgetStore(fileURL: directory.appending(path: "snapshot.json"))
        let repository = SchoolRepository(
            client: MockBakalariClient(permanentTimetableResult: permanent),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(),
            nextLessonWidgetStore: store
        )
        _ = try await repository.loadTimetable(weekContaining: monday)
        let weeklySnapshot = try #require(try store.loadSnapshot())
        _ = try await repository.loadTimetable(weekContaining: monday, kind: .permanent)
        _ = repository.loadCachedTimetable(weekContaining: monday, kind: .permanent)
        #expect(try store.loadSnapshot() == weeklySnapshot)
    }

    private func repository(client: any BakalariClient, cache: any TimetableCaching = InMemoryTimetableCache()) -> SchoolRepository {
        SchoolRepository(
            client: client,
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(),
            timetableCache: cache
        )
    }
}

private final class TimetableEndpointURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"Hours\":[],\"Days\":[]}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
private final class DelayedWeeklyTimetableClient: BakalariClient {
    private let mock: MockBakalariClient
    private var weeklyRequest: CheckedContinuation<TimetableResponse, Never>?
    private var requestStarted: CheckedContinuation<Void, Never>?

    init(permanent: TimetableResponse) {
        mock = MockBakalariClient(permanentTimetableResult: permanent)
    }

    func waitForWeeklyRequest() async {
        guard weeklyRequest == nil else { return }
        await withCheckedContinuation { requestStarted = $0 }
    }

    func completeWeeklyRequest() {
        weeklyRequest?.resume(returning: PreviewData.timetableResponse)
        weeklyRequest = nil
    }

    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse {
        await withCheckedContinuation {
            weeklyRequest = $0
            requestStarted?.resume()
            requestStarted = nil
        }
    }

    func fetchPermanentTimetable(baseURL: URL, accessToken: String) async throws -> TimetableResponse {
        try await mock.fetchPermanentTimetable(baseURL: baseURL, accessToken: accessToken)
    }

    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse { mock.loginResult }
    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse { mock.loginResult }
    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse { mock.marksResult }
    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse { mock.absenceResult }
    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse { PreviewData.userResponse }
    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject { subject }
}
