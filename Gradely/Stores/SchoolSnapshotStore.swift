import Foundation
import Observation

struct SchoolRefreshRequirements: OptionSet {
    let rawValue: Int
    static let marks = Self(rawValue: 1 << 0)
    static let timetable = Self(rawValue: 1 << 1)
    static let history = Self(rawValue: 1 << 2)
    static let absence = Self(rawValue: 1 << 3)
    static let user = Self(rawValue: 1 << 4)
    static let today: Self = [.marks, .timetable, .history, .absence, .user]
    static let subjects: Self = [.marks, .history, .absence, .user]
}

struct SchoolSourceFreshness: Equatable {
    var lastSuccessAt: Date?
    var isRefreshing = false
    var error: String?

    func isStale(at now: Date, interval: TimeInterval) -> Bool {
        guard let lastSuccessAt, error == nil else { return true }
        let age = now.timeIntervalSince(lastSuccessAt)
        return age < 0 || age >= interval
    }
}

/// The app's shared school read model. Provider caches remain the durable source.
@MainActor @Observable
final class SchoolSnapshotStore {
    private(set) var scope: SchoolDataScope?
    private(set) var subjects: [Subject] = []
    private(set) var preparedCalculations: [String: PreparedGradeCalculation] = [:]
    private(set) var timetableWeeks: [String: TimetableWeek] = [:]
    private(set) var history = GradeHistoryResponse(events: [], recentNewMarkEvents: [])
    private(set) var absence: AbsenceData?
    private(set) var user: UserResponse?
    private(set) var freshness: [String: SchoolSourceFreshness] = [:]
    private(set) var revision = 0
    let plannerStore: PlannerStore
    let repository: SchoolRepository
    private let historyRepository: GradeyHistoryRepository?
    private let now: () -> Date
    private let historyDirectory: URL?
    private let insightState: SchoolInsightStateStore
    private(set) var observations: [SchoolGradeObservation] = []
    @ObservationIgnored private var activeIdentity: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(repository: SchoolRepository, historyRepository: GradeyHistoryRepository? = nil,
         plannerStore: PlannerStore? = nil, historyDirectory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.historyRepository = historyRepository
        self.plannerStore = plannerStore ?? PlannerStore(persistence: InMemoryPlannerPersistence(), calendarService: UnavailablePlannerCalendarService())
        self.historyDirectory = historyDirectory
        self.insightState = SchoolInsightStateStore(directory: historyDirectory)
        self.now = now
    }

    var marksFetchedAt: Date? { freshness["marks"]?.lastSuccessAt }
    var isRefreshing: Bool { freshness.values.contains(where: \.isRefreshing) }
    var events: [SchoolEvent] { PlannerEventProjection.events(from: plannerStore.items, scope: scope) }

    var subjectInsights: [SubjectInsightSummary] {
        guard let scope else { return [] }
        return SubjectInsightEngine.make(subjects: subjects, preparedCalculations: preparedCalculations,
                                  observations: observations, events: events, scope: scope, now: now())
    }
    func todayInsights(at date: Date = Date()) -> [TodayInsight] {
        TodayInsightEngine.make(subjectInsights: subjectInsights, events: events, marksFetchedAt: marksFetchedAt,
                                now: date, calendar: .current,
                                schoolDataIsStale: sourceState("marks").isStale(at: date, interval: 300))
    }
    func markSeen(_ insights: [TodayInsight]) {
        guard let scope else { return }
        insightState.markSeen(insights.flatMap(\.observationIDs), scope: scope, at: now())
        observations = insightState.observations(scope: scope, now: now())
    }
    func clearDerivedState(scope affectedScope: SchoolDataScope?) {
        if let affectedScope { insightState.clear(scope: affectedScope) }
        else { insightState.clearAll() }
        if let directory = historyDirectory {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in urls where affectedScope.map({ url.lastPathComponent == $0.filename(prefix: "grade-history-cache") }) ?? url.lastPathComponent.hasPrefix("grade-history-cache-") {
                try? FileManager.default.removeItem(at: url)
            }
        }
        if affectedScope == nil || affectedScope == scope { invalidateSession() }
    }

    func subject(id: String) -> Subject? { subjects.first { $0.id == id } }
    func cachedWeek(containing date: Date) -> TimetableWeek? { timetableWeeks[weekKey(date)] }
    func sourceState(_ key: String) -> SchoolSourceFreshness { freshness[key] ?? SchoolSourceFreshness() }

    /// Returns whether the identity changed. No network is necessary to populate a screen.
    @discardableResult func activateCurrentScope() -> Bool {
        let session = try? repository.currentStoredSession()
        let identity = session.map {
            [$0.cacheScope, $0.provider.rawValue, $0.baseURL.absoluteString,
             $0.bakalari?.username ?? "", $0.eduPage?.activeStudent?.id ?? "", repository.sessionGeneration.uuidString].joined(separator: "\u{1F}")
        }
        guard identity != activeIdentity else { return false }
        invalidateSession()
        activeIdentity = identity
        guard let session else { return true }
        scope = SchoolDataScope(session: session)
        plannerStore.loadIfNeeded()
        if let cached = try? repository.loadCachedMarks() {
            acceptMarks(cached.marksResponse.subjects, at: cached.cachedAt, isCached: true)
        }
        if let cached = try? repository.loadCachedAbsence() {
            absence = AbsenceData(response: cached.response, absencesPerSubject: cached.response.absencesPerSubject,
                                  subjectResolutionSource: .official, user: nil)
            freshness["absence"] = SchoolSourceFreshness(lastSuccessAt: cached.cachedAt)
        }
        for date in [now(), TimetableDates.addingWeeks(1, to: now())] {
            let key = weekKey(date)
            if let week = repository.loadCachedTimetable(weekContaining: date, publishSummaries: false) {
                timetableWeeks[key] = week
                freshness["timetable-\(key)"] = SchoolSourceFreshness(lastSuccessAt: repository.cachedTimetableDate(weekContaining: date))
            }
        }
        if marksFetchedAt == nil, let scope { observations = insightState.activate(subjects: [], scope: scope, fetchedAt: nil, now: now()) }
        loadCachedHistory()
        revision += 1
        return true
    }

    func invalidateSession() {
        generation = UUID()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        activeIdentity = nil
        scope = nil
        subjects = []
        preparedCalculations = [:]
        observations = []
        timetableWeeks = [:]
        history = GradeHistoryResponse(events: [], recentNewMarkEvents: [])
        absence = nil
        user = nil
        freshness = [:]
        revision += 1
    }

    func refresh(requirements: SchoolRefreshRequirements = .today, force: Bool = false) async {
        activateCurrentScope()
        guard scope != nil else { return }
        let requestedGeneration = generation
        let requestedSession = repository.sessionGeneration
        var pending: [Task<Void, Never>] = []
        if requirements.contains(.marks) { pending.append(start(key: "marks", ttl: 300, force: force) { [self] in
            let result = try await repository.loadMarks(forceRefresh: force)
            guard generation == requestedGeneration, repository.sessionGeneration == requestedSession else { throw CancellationError() }
            acceptMarks(result.subjects, at: now(), isCached: false)
        }) }
        if requirements.contains(.timetable) { pending.append(startTimetable(containing: now(), force: force)) }
        if requirements.contains(.history), let historyRepository,
           let session = try? repository.currentStoredSession(), session.provider != .eduPage,
           let accountID = session.linkedAccountID {
            pending.append(start(key: "history", ttl: 900, force: force) { [self] in
            let result = try await historyRepository.loadGradeHistory(linkedAccountID: accountID, days: 400)
            guard generation == requestedGeneration, repository.sessionGeneration == requestedSession else { throw CancellationError() }
            history = result
            saveHistory(result)
        }) }
        if requirements.contains(.absence) { pending.append(start(key: "absence", ttl: 900, force: force) { [self] in
            let result = try await repository.loadAbsence(forceRefresh: force, includeUser: false)
            guard generation == requestedGeneration, repository.sessionGeneration == requestedSession else { throw CancellationError() }
            absence = result
            if let loadedUser = result.user { user = loadedUser }
        }) }
        if requirements.contains(.user) { pending.append(start(key: "user", ttl: 900, force: force) { [self] in
            guard let result = await repository.loadUser() else { throw AppError.unknown(AppL10n.string("error.unknown")) }
            guard generation == requestedGeneration, repository.sessionGeneration == requestedSession else { throw CancellationError() }
            user = result
        }) }
        for task in pending { await task.value }
    }

    func refreshTimetable(containing date: Date, force: Bool = false) async {
        activateCurrentScope()
        guard scope != nil else { return }
        await startTimetable(containing: date, force: force).value
    }

    private func startTimetable(containing date: Date, force: Bool) -> Task<Void, Never> {
        let key = weekKey(date), requestedGeneration = generation
        let requestedSession = repository.sessionGeneration
        return start(key: "timetable-\(key)", ttl: 900, force: force) { [self] in
            let week = try await repository.loadTimetable(weekContaining: date, publishSummaries: Calendar.current.isDate(date, equalTo: now(), toGranularity: .weekOfYear))
            guard generation == requestedGeneration, repository.sessionGeneration == requestedSession else { throw CancellationError() }
            timetableWeeks[key] = week
        }
    }

    private func start(key: String, ttl: TimeInterval, force: Bool, operation: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        if let task = tasks[key] { return task }
        if !force && !sourceState(key).isStale(at: now(), interval: ttl) { return Task {} }
        let requestedGeneration = generation
        let requestedSessionGeneration = repository.sessionGeneration
        var state = sourceState(key)
        state.isRefreshing = true
        freshness[key] = state
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == requestedGeneration {
                    self.freshness[key]?.isRefreshing = false
                    self.tasks[key] = nil
                    self.revision += 1
                }
            }
            do {
                try await operation()
                guard self.generation == requestedGeneration,
                      self.repository.sessionGeneration == requestedSessionGeneration else { return }
                self.freshness[key] = SchoolSourceFreshness(lastSuccessAt: self.now())
            } catch {
                guard self.generation == requestedGeneration else { return }
                if !(error is CancellationError) { self.freshness[key]?.error = error.localizedDescription }
            }
        }
        tasks[key] = task
        return task
    }

    private func acceptMarks(_ incoming: [Subject], at date: Date, isCached: Bool) {
        subjects = incoming
        var prepared: [String: PreparedGradeCalculation] = [:]
        for subject in incoming {
            let digest = GradeMath.revision(for: subject)
            prepared[subject.id] = preparedCalculations[subject.id].flatMap { $0.revision == digest ? $0 : nil } ?? GradeMath.prepare(subject)
        }
        preparedCalculations = prepared
        if let scope {
            observations = isCached
                ? insightState.activate(subjects: incoming, scope: scope, fetchedAt: date, preparedCalculations: prepared, now: now())
                : insightState.observe(subjects: incoming, scope: scope, fetchedAt: date, preparedCalculations: prepared)
        }
        freshness["marks"] = SchoolSourceFreshness(lastSuccessAt: date)
        revision += 1
    }

    private func weekKey(_ date: Date) -> String { TimetableDates.apiDateString(TimetableDates.monday(of: date)) }
    private var historyURL: URL? { scope.flatMap { scope in historyDirectory?.appending(path: scope.filename(prefix: "grade-history-cache")) } }
    private struct HistoryCache: Codable { let response: GradeHistoryResponse; let fetchedAt: Date }
    private func loadCachedHistory() {
        // Cloud history has no EduPage child identity. A scoped filename cannot
        // make account-wide rows comparable with the currently selected child.
        guard (try? repository.currentStoredSession())?.provider != .eduPage,
              let url = historyURL, let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder.sessionDecoder.decode(HistoryCache.self, from: data) else { return }
        history = cached.response
        freshness["history"] = SchoolSourceFreshness(lastSuccessAt: cached.fetchedAt)
    }
    private func saveHistory(_ response: GradeHistoryResponse) {
        guard let url = historyURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.sessionEncoder.encode(HistoryCache(response: response, fetchedAt: now()))
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch { /* Optional history caching never discards the last good snapshot. */ }
    }
}
