import Foundation
#if !os(macOS)
import GradelyWatchShared
#endif
#if canImport(WidgetKit) && (os(iOS) || os(macOS))
import WidgetKit
#endif

struct DashboardData: Equatable {
    let marksResponse: MarksResponse
    let absencesPerSubject: [AbsencePerSubject]
    let user: UserResponse?
}

struct AbsenceData: Equatable {
    let response: AbsenceResponse
    let absencesPerSubject: [AbsencePerSubject]
    let subjectResolutionSource: AbsenceSubjectResolutionSource
    let subjectResolutionWarning: String?
    let subjectStableIDHints: [String]
    let unresolvedPartialDays: [AbsencePartialDayCandidate]
    let user: UserResponse?

    init(
        response: AbsenceResponse,
        absencesPerSubject: [AbsencePerSubject],
        subjectResolutionSource: AbsenceSubjectResolutionSource,
        subjectResolutionWarning: String? = nil,
        subjectStableIDHints: [String] = [],
        unresolvedPartialDays: [AbsencePartialDayCandidate] = [],
        user: UserResponse?
    ) {
        self.response = response
        self.absencesPerSubject = absencesPerSubject
        self.subjectResolutionSource = subjectResolutionSource
        self.subjectResolutionWarning = subjectResolutionWarning
        self.subjectStableIDHints = subjectStableIDHints
        self.unresolvedPartialDays = unresolvedPartialDays
        self.user = user
    }
}

enum AbsenceSubjectResolutionSource: Equatable {
    case official
    case synthesized
    case partialSynthesized
    case unavailable
}

struct AbsenceSubjectResolutionProgress: Equatable {
    let loadedWeeks: Int
    let completedWeeks: Int
    let totalWeeks: Int
}

enum AppError: LocalizedError, Equatable {
    case notLoggedIn
    case missingFields
    case unknown(String)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                return AppL10n.string("error.notLoggedIn")
            case .missingFields:
                return AppL10n.string("error.missingFields")
            case .unknown(let message):
                return message
            }
        }
}

final class SchoolRepository {
    private let client: any BakalariClient
    private let eduPageClient: any EduPageClient
    private let sessionStore: any SessionStoring
    private let marksCache: any MarksCaching
    private let absenceCache: any AbsenceCaching
    private let timetableCache: any TimetableCaching
    private let nextLessonWidgetStore: (any NextLessonWidgetStoring)?
    private let absenceLessonSelectionStore: any AbsenceLessonSelectionStoring
    private let schoolDirectoryProvider: (any SchoolDirectoryProviding)?
    private let watchSyncService: (any WatchSyncing)?
    private let dateProvider: () -> Date
    private let timetableFetchTimeoutNanoseconds: UInt64
    private var pendingEduPageBaseURL: URL?
    /// In-flight Bakaláři token refresh, shared by concurrent callers so the
    /// rotating refresh token is never redeemed twice in parallel.
    private var bakalariRefreshTask: Task<StoredSession, Error>?
    private var bakalariRefreshGeneration: UUID?
    private var markRequests: [String: Task<MarksResponse, Error>] = [:]
    private var absenceRequests: [String: Task<AbsenceResponse, Error>] = [:]
    private var userRequests: [String: Task<UserResponse, Error>] = [:]
    private var timetableRequests: [String: Task<TimetableResponse, Error>] = [:]
    private(set) var sessionGeneration = UUID()
    var onSchoolCacheInvalidation: ((SchoolDataScope?) -> Void)?

    private struct RequestContext {
        let generation: UUID
        let identity: String
    }

    /// Token rotation leaves identity unchanged; replacing the user invalidates all work.
    private func identity(of session: StoredSession) -> String {
        [session.provider.rawValue, session.baseURL.absoluteString,
         session.linkedAccountID ?? "", session.bakalari?.username ?? "",
         session.eduPage?.userID ?? "", session.eduPage?.activeStudent?.id ?? ""]
            .joined(separator: "\u{1F}")
    }

    private func context(for session: StoredSession) -> RequestContext {
        RequestContext(generation: sessionGeneration, identity: identity(of: session))
    }

    private func validate(_ context: RequestContext) throws {
        try Task.checkCancellation()
        guard context.generation == sessionGeneration,
              let current = try sessionStore.loadSession(),
              identity(of: current) == context.identity else { throw CancellationError() }
    }

    private func invalidateRequests() {
        sessionGeneration = UUID()
        bakalariRefreshTask?.cancel()
        bakalariRefreshTask = nil
        bakalariRefreshGeneration = nil
        markRequests.values.forEach { $0.cancel() }
        absenceRequests.values.forEach { $0.cancel() }
        userRequests.values.forEach { $0.cancel() }
        timetableRequests.values.forEach { $0.cancel() }
        markRequests.removeAll()
        absenceRequests.removeAll()
        userRequests.removeAll()
        timetableRequests.removeAll()
        try? nextLessonWidgetStore?.clear()
        watchSyncService?.update(user: nil)
        #if !os(macOS)
        watchSyncService?.update(timetable: nil)
        #endif
        #if canImport(WidgetKit) && (os(iOS) || os(macOS))
        WidgetCenter.shared.reloadTimelines(ofKind: NextLessonWidgetConstants.widgetKind)
        #endif
    }

    private func requestKey(session: StoredSession, suffix: String = "") -> String {
        sessionGeneration.uuidString + "\u{1F}" + identity(of: session) + "\u{1F}" + suffix
    }

    init(
        client: any BakalariClient,
        eduPageClient: any EduPageClient = URLSessionEduPageClient(),
        sessionStore: any SessionStoring,
        marksCache: any MarksCaching,
        absenceCache: any AbsenceCaching = InMemoryAbsenceCache(),
        timetableCache: any TimetableCaching = InMemoryTimetableCache(),
        nextLessonWidgetStore: (any NextLessonWidgetStoring)? = nil,
        absenceLessonSelectionStore: any AbsenceLessonSelectionStoring = InMemoryAbsenceLessonSelectionStore(),
        schoolDirectoryProvider: (any SchoolDirectoryProviding)? = nil,
        watchSyncService: (any WatchSyncing)? = nil,
        dateProvider: @escaping () -> Date = Date.init,
        timetableFetchTimeoutNanoseconds: UInt64 = 12_000_000_000
    ) {
        self.client = client
        self.eduPageClient = eduPageClient
        self.sessionStore = sessionStore
        self.marksCache = marksCache
        self.absenceCache = absenceCache
        self.timetableCache = timetableCache
        self.nextLessonWidgetStore = nextLessonWidgetStore
        self.absenceLessonSelectionStore = absenceLessonSelectionStore
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.watchSyncService = watchSyncService
        self.dateProvider = dateProvider
        self.timetableFetchTimeoutNanoseconds = timetableFetchTimeoutNanoseconds
    }

    func bootstrapSession() throws -> StoredSession? {
        let session = try sessionStore.loadSession()
        if let session {
            watchSyncService?.update(session: session)
        } else {
            watchSyncService?.publishSignedOut()
        }
        return session
    }

    func currentStoredSession() throws -> StoredSession? {
        try sessionStore.loadSession()
    }

    func login(schoolURL: String, username: String, password: String) async throws -> StoredSession {
        let step = try await beginLogin(
            provider: .bakalari,
            schoolURL: schoolURL,
            username: username,
            password: password
        )
        guard case .signedIn(let session) = step else {
            throw AppError.unknown("Unexpected Bakaláři authentication step.")
        }
        return session
    }

    func beginLogin(
        provider: SchoolProvider,
        schoolURL: String,
        username: String,
        password: String
    ) async throws -> SchoolLoginStep {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty
        else {
            throw AppError.missingFields
        }

        invalidateRequests()
        let loginGeneration = sessionGeneration
        switch provider {
        case .bakalari:
            let baseURL = try SchoolURLNormalizer.normalizedBaseURL(from: schoolURL)
            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await client.login(
                baseURL: baseURL,
                username: trimmedUsername,
                password: password
            )
            guard loginGeneration == sessionGeneration else { throw CancellationError() }
            try clearSchoolDataCaches()
            // Persist the credentials so refreshes that hit "token already
            // redeemed" can silently re-authenticate (see refreshBakalariSession).
            let session = try persistBakalariSession(
                from: response,
                baseURL: baseURL,
                credentials: BakalariCredentials(username: trimmedUsername, password: password)
            )
            return .signedIn(session)

        case .eduPage:
            let baseURL = try EduPageURLNormalizer.normalizedBaseURL(from: schoolURL)
            pendingEduPageBaseURL = baseURL
            let result = try await eduPageClient.beginLogin(baseURL: baseURL, username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            guard loginGeneration == sessionGeneration else { throw CancellationError() }
            return try mapEduPageLoginResult(result, baseURL: baseURL)
        }
    }

    func completeEduPageTwoFactor(code: String) async throws -> SchoolLoginStep {
        guard let baseURL = pendingEduPageBaseURL else {
            throw SchoolAuthenticationError.twoFactorRequired
        }
        let generation = sessionGeneration
        let result = try await eduPageClient.completeTwoFactor(code: code)
        guard generation == sessionGeneration else { throw CancellationError() }
        return try mapEduPageLoginResult(result, baseURL: baseURL)
    }

    func completeApprovedEduPageTwoFactor() async throws -> SchoolLoginStep {
        guard let baseURL = pendingEduPageBaseURL else {
            throw SchoolAuthenticationError.twoFactorRequired
        }
        let generation = sessionGeneration
        let result = try await eduPageClient.completeApprovedTwoFactor()
        guard generation == sessionGeneration else { throw CancellationError() }
        return try mapEduPageLoginResult(result, baseURL: baseURL)
    }

    func isEduPageTwoFactorConfirmed() async throws -> Bool {
        try await eduPageClient.isTwoFactorConfirmed()
    }

    func resendEduPageTwoFactorNotification() async throws {
        try await eduPageClient.resendTwoFactorNotification()
    }

    func selectEduPageStudent(_ studentID: String) async throws -> StoredSession {
        guard let baseURL = pendingEduPageBaseURL else {
            throw SchoolAuthenticationError.invalidStudent
        }
        let generation = sessionGeneration
        let data = try await eduPageClient.selectStudent(studentID)
        guard generation == sessionGeneration else { throw CancellationError() }
        invalidateRequests()
        let session = makeEduPageStoredSession(data: data, baseURL: baseURL)
        try clearSchoolDataCaches()
        try sessionStore.save(session: session)
        pendingEduPageBaseURL = nil
        watchSyncService?.update(session: session)
        return session
    }

    var currentProvider: SchoolProvider? {
        (try? sessionStore.loadSession())?.provider
    }

    var availableStudents: [SchoolStudentProfile] {
        (try? sessionStore.loadSession())?.eduPage?.linkedStudents ?? []
    }

    func switchEduPageStudent(_ studentID: String) async throws {
        guard var session = try sessionStore.loadSession(),
              session.provider == .eduPage,
              let eduPage = session.eduPage
        else {
            throw SchoolAuthenticationError.invalidStudent
        }
        let requestContext = context(for: session)
        session.eduPage = try await eduPageClient.switchStudent(studentID, in: eduPage, baseURL: session.baseURL)
        try validate(requestContext)
        invalidateRequests()
        session.accessToken = session.eduPage?.sessionID ?? session.accessToken
        try sessionStore.save(session: session)
        let scope = SchoolDataScope(session: session)
        onSchoolCacheInvalidation?(scope)
        try marksCache.clear(scope: scope)
        try absenceCache.clear(scope: scope)
        try timetableCache.clear(scope: scope)
        try? nextLessonWidgetStore?.clear()
        watchSyncService?.update(session: session)
    }

    func activateLinkedSchoolAccount(_ activation: LinkedSchoolAccountActivation) async throws -> StoredSession {
        let incoming = activation.makeStoredSession()

        if let existing = try sessionStore.loadSession(),
           shouldKeepLocalSchoolSession(existing, insteadOf: incoming) {
            var preserved = existing
            preserved.linkedAccountID = incoming.linkedAccountID
            preserved.linkedAccountDisplayName = incoming.linkedAccountDisplayName
            preserved.linkedAccountSchoolName = incoming.linkedAccountSchoolName
            invalidateRequests()
            try sessionStore.save(session: preserved)
            watchSyncService?.update(session: preserved)
            NotificationCenter.default.post(name: .gradelySchoolAccountDidChange, object: nil)
            return preserved
        }

        if incoming.provider == .bakalari {
            // A new device signs in directly to school; it must never adopt the
            // cloud poller's rotating refresh token or download a password.
            throw SchoolAuthenticationError.deviceSignInRequired
        }

        invalidateRequests()
        try sessionStore.save(session: incoming)
        watchSyncService?.update(session: incoming)
        NotificationCenter.default.post(name: .gradelySchoolAccountDidChange, object: nil)
        return incoming
    }

    /// Keeps a freshly authenticated local provider session associated with its
    /// existing Gradey cloud account after a reconnect.
    func associateCurrentSession(with account: LinkedAccount) throws {
        guard var session = try sessionStore.loadSession(),
              account.provider == LinkedAccountProvider(schoolProvider: session.provider)
        else {
            throw AppError.notLoggedIn
        }

        if session.linkedAccountID != account.id { invalidateRequests() }
        session.linkedAccountID = account.id
        session.linkedAccountDisplayName = account.displayName
        session.linkedAccountSchoolName = account.schoolName
        try sessionStore.save(session: session)
        watchSyncService?.update(session: session)
    }

    /// Prefers the device's own Bakaláři token family over the cloud poller's.
    /// Sharing a rotating refresh token with polling is what marks the school
    /// account as needing a reconnect.
    private func shouldKeepLocalSchoolSession(
        _ existing: StoredSession,
        insteadOf incoming: StoredSession
    ) -> Bool {
        guard existing.provider == incoming.provider else { return false }
        guard existing.baseURL == incoming.baseURL else { return false }
        guard let existingID = existing.linkedAccountID, let incomingID = incoming.linkedAccountID else {
            return false
        }
        return existingID == incomingID
    }

    private func mapEduPageLoginResult(
        _ result: EduPageLoginResult,
        baseURL: URL
    ) throws -> SchoolLoginStep {
        switch result {
        case .twoFactor(let prompt):
            return .twoFactor(prompt)
        case .studentSelection(let students):
            return .studentSelection(students)
        case .authenticated(let data):
            let session = makeEduPageStoredSession(data: data, baseURL: baseURL)
            invalidateRequests()
            try clearSchoolDataCaches()
            try sessionStore.save(session: session)
            pendingEduPageBaseURL = nil
            watchSyncService?.update(session: session)
            return .signedIn(session)
        }
    }

    private func makeEduPageStoredSession(data: EduPageSessionData, baseURL: URL) -> StoredSession {
        StoredSession(
            accessToken: data.sessionID,
            refreshToken: "",
            tokenType: "Cookie",
            expiresAt: .distantFuture,
            baseURL: baseURL,
            provider: .eduPage,
            eduPage: data
        )
    }

    private func clearSchoolDataCaches() throws {
        if let session = try? sessionStore.loadSession() {
            let scope = SchoolDataScope(session: session)
            onSchoolCacheInvalidation?(scope)
            try marksCache.clear(scope: scope)
            try absenceCache.clear(scope: scope)
            try timetableCache.clear(scope: scope)
        } else {
            onSchoolCacheInvalidation?(nil)
            try marksCache.clear()
            try absenceCache.clear()
            try timetableCache.clear()
        }
        try absenceLessonSelectionStore.clearAll()
        try? nextLessonWidgetStore?.clear()
    }

    func clearLocalCaches() throws {
        invalidateRequests()
        onSchoolCacheInvalidation?(nil)
        try marksCache.clear()
        try absenceCache.clear()
        try timetableCache.clear()
        try? nextLessonWidgetStore?.clear()
        try absenceLessonSelectionStore.clearAll()
        #if canImport(WidgetKit) && (os(iOS) || os(macOS))
        WidgetCenter.shared.reloadTimelines(ofKind: NextLessonWidgetConstants.widgetKind)
        #endif
    }

    func logout() throws {
        invalidateRequests()
        try sessionStore.clearSession()
        try clearLocalCaches()
        watchSyncService?.publishSignedOut()
    }

    func loadCachedMarks() throws -> CachedMarks? {
        guard let session = try sessionStore.loadSession() else {
            return try marksCache.load()
        }
        return try marksCache.load(scope: SchoolDataScope(session: session))
    }

    func loadCachedAbsence() throws -> CachedAbsence? {
        guard let session = try sessionStore.loadSession() else {
            return try absenceCache.load()
        }
        return try absenceCache.load(scope: SchoolDataScope(session: session))
    }

    var supportsPermanentTimetable: Bool { currentProvider == .bakalari }

    /// Cached week for instant/offline display, if it matches the requested week.
    func loadCachedTimetable(weekContaining date: Date, kind: TimetableKind = .weekly, publishSummaries: Bool = true) -> TimetableWeek? {
        guard kind == .weekly || supportsPermanentTimetable else { return nil }
        let monday = TimetableDates.monday(of: date)
        let scope = (try? sessionStore.loadSession()).map(SchoolDataScope.init(session:))
        let cached: CachedTimetable?
        if let scope {
            cached = try? timetableCache.load(weekStart: monday, scope: scope, kind: kind)
        } else {
            cached = try? timetableCache.load(weekStart: monday, kind: kind)
        }
        guard let cached else { return nil }
        let week = TimetableMapper.makeWeek(from: cached.response, weekStart: monday, kind: kind)
        if kind == .weekly && publishSummaries {
            publishNextLessonWidgetSnapshot(for: week, weekStart: monday, cachedAt: cached.cachedAt)
            publishWatchTimetable(for: week, cachedAt: cached.cachedAt)
        }
        return week
    }

    /// Fetches and denormalizes the timetable for the week containing `date`, caching the raw response.
    func loadTimetable(weekContaining date: Date, kind: TimetableKind = .weekly, publishSummaries: Bool = true) async throws -> TimetableWeek {
        let monday = TimetableDates.monday(of: date)
        let session = try await validSession()
        let requestContext = context(for: session)
        let response = try await fetchTimetable(session: session, weekStart: monday, kind: kind)
        try validate(requestContext)
        try? timetableCache.save(response, weekStart: monday, scope: SchoolDataScope(session: session), kind: kind)
        let week = TimetableMapper.makeWeek(from: response, weekStart: monday, kind: kind)
        if kind == .weekly && publishSummaries {
            publishNextLessonWidgetSnapshot(for: week, weekStart: monday)
            publishWatchTimetable(for: week, cachedAt: dateProvider())
        }
        return week
    }

    func loadAbsencePredictionLessons(
        on date: Date,
        user: UserResponse?
    ) async throws -> [AbsenceLessonCandidate] {
        _ = user
        let weekStart = TimetableDates.monday(of: date)
        let session = try await validSession()
        let scope = SchoolDataScope(session: session)

        let response: TimetableResponse
        if let cached = try? timetableCache.load(weekStart: weekStart, scope: scope) {
            response = cached.response
        } else {
            response = try await fetchTimetable(session: session, weekStart: weekStart)
            try? timetableCache.save(response, weekStart: weekStart, scope: scope)
        }

        let marksResponse = try? await marksResponseForAbsenceFallback(session: session)
        return AbsenceTimetableLessonResolver.candidates(
            on: date,
            in: response,
            subjects: marksResponse?.subjects ?? []
        )
    }

    /// Best-effort current user, used to populate the account menu on tabs other than Marks.
    func loadUser() async -> UserResponse? {
        guard let session = try? await validSession() else { return nil }
        let requestContext = context(for: session)
        guard let user = try? await fetchUser(session: session), (try? validate(requestContext)) != nil else {
            return nil
        }
        let resolved = resolvedUser(user, session: session)
        if let resolved {
            watchSyncService?.update(user: resolved)
        }
        return resolved
    }

    /// Fetch grades independently so a slow optional source cannot delay their display.
    func loadMarks(forceRefresh: Bool = false) async throws -> MarksResponse {
        let session = try await validSession()
        let requestContext = context(for: session)
        let response = try await fetchMarks(session: session)
        try validate(requestContext)
        try marksCache.save(response, scope: SchoolDataScope(session: session))
        return response
    }

    func cachedTimetableDate(weekContaining date: Date, kind: TimetableKind = .weekly) -> Date? {
        guard let session = try? sessionStore.loadSession() else { return nil }
        return try? timetableCache.load(weekStart: TimetableDates.monday(of: date), scope: SchoolDataScope(session: session), kind: kind)?.cachedAt
    }

    func loadDashboard(forceRefresh: Bool = false) async throws -> DashboardData {
        let session = try await validSession()
        let requestContext = context(for: session)
        let marksResponse = try await loadMarks(forceRefresh: forceRefresh)
        async let absenceResponse = optionalAbsenceResponse(session: session)
        async let user = optionalUser(session: session)
        let absence = await absenceResponse
        let loadedUser = await user
        try validate(requestContext)
        if let absence { try? absenceCache.save(absence, scope: SchoolDataScope(session: session)) }
        let resolved = resolvedUser(loadedUser, session: session)
        if let resolved { watchSyncService?.update(user: resolved) }
        return DashboardData(marksResponse: marksResponse, absencesPerSubject: absence?.absencesPerSubject ?? [], user: resolved)
    }

    func loadAbsence(forceRefresh: Bool = false, includeUser: Bool = true) async throws -> AbsenceData {
        let session = try await validSession()
        let scope = SchoolDataScope(session: session)
        let requestContext = context(for: session)
        async let user: UserResponse? = includeUser ? optionalUser(session: session) : nil

        let response = try await fetchAbsences(session: session)
        try validate(requestContext)
        try? absenceCache.save(response, scope: scope)

        let resolvedAbsenceUser = resolvedUser(await user, session: session)
        try validate(requestContext)
        if let resolvedAbsenceUser {
            watchSyncService?.update(user: resolvedAbsenceUser)
        }

        return AbsenceData(
            response: response,
            absencesPerSubject: response.absencesPerSubject,
            subjectResolutionSource: response.absencesPerSubject.isEmpty ? .unavailable : .official,
            user: resolvedAbsenceUser
        )
    }

    func resolveAbsencesPerSubject(
        from response: AbsenceResponse,
        user: UserResponse? = nil,
        progress: ((AbsenceSubjectResolutionProgress) async -> Void)? = nil
    ) async throws -> AbsenceData {
        guard response.absencesPerSubject.isEmpty else {
            return AbsenceData(
                response: response,
                absencesPerSubject: response.absencesPerSubject,
                subjectResolutionSource: .official,
                user: nil
            )
        }

        guard !response.absences.isEmpty else {
            return AbsenceData(
                response: response,
                absencesPerSubject: [],
                subjectResolutionSource: .unavailable,
                user: nil
            )
        }

        let session = try await validSession()
        let requestContext = context(for: session)
        let selectionScope = absenceLessonSelectionScope(session: session, user: user)
        let manualSelections = (try? absenceLessonSelectionStore.load(scope: selectionScope)) ?? .empty
        let marksResponse = try? await marksResponseForAbsenceFallback(session: session)
        let term = AbsenceSubjectFallback.term(
            for: response.absences,
            now: dateProvider()
        )
        let timetables = await loadTermTimetableResponses(
            weekStarts: term.weekStarts,
            session: session,
            progress: progress
        )

        try validate(requestContext)
        guard !timetables.responses.isEmpty else {
            throw AbsenceSubjectResolutionError.noUsableTimetable
        }

        let resolved = AbsenceSubjectFallback.makeAbsenceResult(
            from: response,
            timetableResponses: timetables.responses,
            subjects: marksResponse?.subjects ?? [],
            manualSelections: manualSelections,
            validDateRange: term.start...term.end
        )
        let hasPartialTimetable = timetables.failedWeeks > 0
        let warning = hasPartialTimetable ? AppL10n.string("absence.subjects.partial.warning") : nil

        return AbsenceData(
            response: response,
            absencesPerSubject: resolved.absences,
            subjectResolutionSource: resolved.absences.isEmpty ? .unavailable : (hasPartialTimetable ? .partialSynthesized : .synthesized),
            subjectResolutionWarning: warning,
            subjectStableIDHints: resolved.stableIDHints,
            unresolvedPartialDays: resolved.unresolvedPartialDays,
            user: nil
        )
    }

    func saveManualAbsenceLessonSelections(
        selectedLessonIDsByDate: [String: Set<String>],
        user: UserResponse?
    ) async throws {
        let session = try await validSession()
        let scope = absenceLessonSelectionScope(session: session, user: user)
        var selections = try absenceLessonSelectionStore.load(scope: scope)

        for (dateKey, lessonIDs) in selectedLessonIDsByDate {
            selections.selectedLessonIDsByDate[dateKey] = Array(lessonIDs).sorted()
        }

        try absenceLessonSelectionStore.save(selections, scope: scope)
    }

    func predictSubjectAverage(subject: Subject, markText: String, weight: Int) async throws -> Double? {
        let session = try await validSession()
        let requestContext = context(for: session)
        try validate(requestContext)
        if !session.provider.capabilities.supportsRemoteWhatIf {
            guard let value = GradeMath.parseMarkValue(markText) else { return nil }
            return GradeMath.theoreticalAverage(
                existingMarks: subject.marks,
                subjectAverageText: subject.averageText,
                markValue: value,
                weight: weight
            )
        }
        let predictedSubject = try await withBakalariRetry(session: session) { current in
            try await self.client.predictSubject(
                baseURL: current.baseURL,
                accessToken: current.accessToken,
                subject: subject,
                markText: markText,
                weight: weight
            )
        }
        try validate(requestContext)
        return GradeMath.parseAverageText(predictedSubject.averageText)
    }

    func validSession() async throws -> StoredSession {
        guard let session = try sessionStore.loadSession() else {
            throw AppError.notLoggedIn
        }

        guard session.provider == .bakalari, session.isExpired else { return session }

        return try await refreshBakalariSession(force: false)
    }

    /// Single-flight wrapper: concurrent callers share one refresh so the
    /// rotating refresh token is redeemed at most once.
    private func refreshBakalariSession(force: Bool) async throws -> StoredSession {
        let generation = sessionGeneration
        if let task = bakalariRefreshTask, bakalariRefreshGeneration == generation {
            return try await task.value
        }
        let task = Task { try await performBakalariRefresh(force: force) }
        bakalariRefreshTask = task
        bakalariRefreshGeneration = generation
        defer {
            if bakalariRefreshGeneration == generation {
                bakalariRefreshTask = nil
                bakalariRefreshGeneration = nil
            }
        }
        return try await task.value
    }

    private func performBakalariRefresh(force: Bool) async throws -> StoredSession {
        guard let session = try sessionStore.loadSession() else { throw AppError.notLoggedIn }
        guard session.provider == .bakalari, force || session.isExpired else { return session }
        let requestContext = context(for: session)
        do {
            let response = try await client.refreshToken(baseURL: session.baseURL, refreshToken: session.refreshToken)
            try validate(requestContext)
            return try persistBakalariSession(from: response, baseURL: session.baseURL, credentials: session.bakalari, metadataFrom: session)
        } catch {
            try validate(requestContext)
            guard isRefreshTokenRejected(error), let credentials = session.bakalari else { throw error }
            let response = try await client.login(baseURL: session.baseURL, username: credentials.username, password: credentials.password)
            try validate(requestContext)
            return try persistBakalariSession(from: response, baseURL: session.baseURL, credentials: credentials, metadataFrom: session)
        }
    }

    private func makeBakalariSession(
        from response: LoginResponse,
        baseURL: URL,
        credentials: BakalariCredentials?,
        metadataFrom existing: StoredSession? = nil
    ) -> StoredSession {
        StoredSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            tokenType: response.tokenType,
            expiresAt: dateProvider().addingTimeInterval(TimeInterval(response.expiresIn)),
            baseURL: baseURL,
            provider: .bakalari,
            bakalari: credentials,
            linkedAccountID: existing?.linkedAccountID,
            linkedAccountDisplayName: existing?.linkedAccountDisplayName,
            linkedAccountSchoolName: existing?.linkedAccountSchoolName
        )
    }

    @discardableResult
    private func persistBakalariSession(
        from response: LoginResponse,
        baseURL: URL,
        credentials: BakalariCredentials?,
        metadataFrom existing: StoredSession? = nil
    ) throws -> StoredSession {
        let session = makeBakalariSession(
            from: response,
            baseURL: baseURL,
            credentials: credentials,
            metadataFrom: existing
        )
        try sessionStore.save(session: session)
        watchSyncService?.update(session: session)
        return session
    }

    /// Runs a Bakaláři request and, if the access token is rejected (HTTP 401),
    /// forces a refresh/re-login and retries the request once.
    private func withBakalariRetry<Value>(
        session: StoredSession,
        operation: (StoredSession) async throws -> Value
    ) async throws -> Value {
        let requestContext = context(for: session)
        try validate(requestContext)
        do {
            let result = try await operation(session)
            try validate(requestContext)
            return result
        } catch {
            try validate(requestContext)
            guard session.provider == .bakalari, isAccessTokenRejected(error) else { throw error }
            // Another request may already have rotated this token. Reuse its result.
            let latest = try sessionStore.loadSession()
            let refreshed: StoredSession
            if let latest, latest.accessToken != session.accessToken {
                refreshed = latest
            } else {
                refreshed = try await refreshBakalariSession(force: true)
            }
            try validate(requestContext)
            let result = try await operation(refreshed)
            try validate(requestContext)
            return result
        }
    }

    /// A rejected refresh token surfaces as HTTP 400 (`invalid_grant` /
    /// "token already redeemed") or 401 from the token endpoint.
    private func isRefreshTokenRejected(_ error: Error) -> Bool {
        if case BakalariAPIError.httpStatus(let status, _) = error {
            return status == 400 || status == 401
        }
        return false
    }

    /// An access token rejected mid-session surfaces as HTTP 401 on a data call.
    private func isAccessTokenRejected(_ error: Error) -> Bool {
        if case BakalariAPIError.httpStatus(401, _) = error {
            return true
        }
        return false
    }

    private func fetchMarks(session: StoredSession) async throws -> MarksResponse {
        let key = requestKey(session: session)
        if let task = markRequests[key] { return try await task.value }
        let task = Task { try await self.performFetchMarks(session: session) }
        markRequests[key] = task
        defer { markRequests[key] = nil }
        return try await task.value
    }

    private func performFetchMarks(session: StoredSession) async throws -> MarksResponse {
        switch session.provider {
        case .bakalari:
            return try await withBakalariRetry(session: session) { current in
                try await self.client.fetchMarks(baseURL: current.baseURL, accessToken: current.accessToken)
            }
        case .eduPage:
            return try await withEduPageSession(session) { data in
                try await self.eduPageClient.fetchMarks(baseURL: session.baseURL, session: data)
            }
        }
    }

    private func fetchAbsences(session: StoredSession) async throws -> AbsenceResponse {
        let key = requestKey(session: session)
        if let task = absenceRequests[key] { return try await task.value }
        let task = Task { try await self.performFetchAbsences(session: session) }
        absenceRequests[key] = task
        defer { absenceRequests[key] = nil }
        return try await task.value
    }

    private func performFetchAbsences(session: StoredSession) async throws -> AbsenceResponse {
        switch session.provider {
        case .bakalari:
            return try await withBakalariRetry(session: session) { current in
                try await self.client.fetchAbsences(baseURL: current.baseURL, accessToken: current.accessToken)
            }
        case .eduPage:
            return try await withEduPageSession(session) { data in
                try await self.eduPageClient.fetchAbsences(baseURL: session.baseURL, session: data)
            }
        }
    }

    private func fetchUser(session: StoredSession) async throws -> UserResponse {
        let key = requestKey(session: session)
        if let task = userRequests[key] { return try await task.value }
        let task = Task { try await self.performFetchUser(session: session) }
        userRequests[key] = task
        defer { userRequests[key] = nil }
        return try await task.value
    }

    private func performFetchUser(session: StoredSession) async throws -> UserResponse {
        switch session.provider {
        case .bakalari:
            return try await withBakalariRetry(session: session) { current in
                try await self.client.fetchUser(baseURL: current.baseURL, accessToken: current.accessToken)
            }
        case .eduPage:
            return try await withEduPageSession(session) { data in
                try await self.eduPageClient.fetchUser(baseURL: session.baseURL, session: data)
            }
        }
    }

    private func fetchTimetable(session: StoredSession, weekStart: Date, kind: TimetableKind = .weekly) async throws -> TimetableResponse {
        let key = requestKey(session: session, suffix: kind.rawValue + "-" + TimetableDates.apiDateString(weekStart))
        if let task = timetableRequests[key] { return try await awaitTimetableRequest(task) }
        let task = Task {
            defer { self.timetableRequests[key] = nil }
            return try await self.performFetchTimetable(session: session, weekStart: weekStart, kind: kind)
        }
        timetableRequests[key] = task
        return try await awaitTimetableRequest(task)
    }

    /// The absence resolver's deadline cancels its waiter, not another screen's shared fetch.
    private func awaitTimetableRequest(_ task: Task<TimetableResponse, Error>) async throws -> TimetableResponse {
        let waiter = TimetableRequestWaiter()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.continuation = continuation
                if Task.isCancelled { waiter.finish(.failure(CancellationError())) }
                else { Task { waiter.finish(await task.result) } }
            }
        } onCancel: {
            Task { @MainActor in waiter.finish(.failure(CancellationError())) }
        }
    }

    private func performFetchTimetable(session: StoredSession, weekStart: Date, kind: TimetableKind) async throws -> TimetableResponse {
        switch session.provider {
        case .bakalari:
            return try await withBakalariRetry(session: session) { current in
                if kind == .permanent {
                    return try await self.client.fetchPermanentTimetable(
                        baseURL: current.baseURL,
                        accessToken: current.accessToken
                    )
                }
                return try await self.client.fetchTimetable(
                    baseURL: current.baseURL,
                    accessToken: current.accessToken,
                    date: weekStart
                )
            }
        case .eduPage:
            guard kind == .weekly else {
                throw AppError.unknown(AppL10n.string("timetable.permanent.unavailable"))
            }
            return try await withEduPageSession(session) { data in
                try await self.eduPageClient.fetchTimetable(
                    baseURL: session.baseURL,
                    session: data,
                    weekStart: weekStart
                )
            }
        }
    }

    private func withEduPageSession<Value>(
        _ stored: StoredSession,
        operation: (EduPageSessionData) async throws -> Value
    ) async throws -> Value {
        guard let data = stored.eduPage else { throw SchoolAuthenticationError.sessionExpired }
        let requestContext = context(for: stored)
        try validate(requestContext)
        do {
            let result = try await operation(data)
            try validate(requestContext)
            return result
        } catch SchoolAuthenticationError.sessionExpired {
            try validate(requestContext)
            let refreshed = try await eduPageClient.restore(data, baseURL: stored.baseURL)
            try validate(requestContext)
            var updated = stored
            updated.accessToken = refreshed.sessionID
            updated.eduPage = refreshed
            try sessionStore.save(session: updated)
            watchSyncService?.update(session: updated)
            let result = try await operation(refreshed)
            try validate(requestContext)
            return result
        }
    }

    private func optionalAbsenceResponse(session: StoredSession) async -> AbsenceResponse? {
        do {
            return try await fetchAbsences(session: session)
        } catch {
            return nil
        }
    }

    private func optionalUser(session: StoredSession) async -> UserResponse? {
        try? await fetchUser(session: session)
    }

    private func resolvedUser(_ user: UserResponse?, session: StoredSession) -> UserResponse? {
        guard let user else { return nil }

        if let displaySchoolName = user.displaySchoolName {
            return user.schoolName == displaySchoolName ? user : user.replacingSchoolName(displaySchoolName)
        }

        guard let schoolDirectoryProvider,
              let cachedDirectory = try? schoolDirectoryProvider.loadCachedDirectory(),
              let directorySchoolName = SchoolNameResolver.directoryName(for: session.baseURL, in: cachedDirectory.schools)
        else {
            return user.replacingSchoolName(nil)
        }

        return user.replacingSchoolName(directorySchoolName)
    }

    private func marksResponseForAbsenceFallback(session: StoredSession) async throws -> MarksResponse {
        let requestContext = context(for: session)
        try validate(requestContext)
        let scope = SchoolDataScope(session: session)
        if let cached = try? marksCache.load(scope: scope) {
            return cached.marksResponse
        }

        let response = try await fetchMarks(session: session)
        try validate(requestContext)
        try? marksCache.save(response, scope: scope)
        return response
    }

    private func absenceLessonSelectionScope(
        session: StoredSession,
        user: UserResponse?
    ) -> AbsenceLessonSelectionScope {
        let userID = user?.userUID.trimmingCharacters(in: .whitespacesAndNewlines)
        return AbsenceLessonSelectionScope(
            baseURL: session.baseURL.absoluteString,
            userID: userID?.isEmpty == false ? userID! : "unknown-user"
        )
    }

    private func loadTermTimetableResponses(
        weekStarts: [Date],
        session: StoredSession,
        progress: ((AbsenceSubjectResolutionProgress) async -> Void)?
    ) async -> TermTimetableLoadResult {
        let totalWeeks = weekStarts.count
        var loaded: [LoadedTimetableWeek] = []
        var missingWeekStarts: [Date] = []
        var lastPublishedCompletedWeeks: Int?

        func publishProgress(force: Bool = false, completedWeeks: Int) async {
            guard let progress else { return }
            let shouldPublish = force
                || lastPublishedCompletedWeeks == nil
                || completedWeeks == totalWeeks
                || completedWeeks - (lastPublishedCompletedWeeks ?? 0) >= 2

            guard shouldPublish else { return }
            lastPublishedCompletedWeeks = completedWeeks
            await progress(
                AbsenceSubjectResolutionProgress(
                    loadedWeeks: loaded.count,
                    completedWeeks: completedWeeks,
                    totalWeeks: totalWeeks
                )
            )
        }

        for weekStart in weekStarts {
            if let cached = try? timetableCache.load(weekStart: weekStart, scope: SchoolDataScope(session: session)) {
                loaded.append(LoadedTimetableWeek(weekStart: weekStart, response: cached.response))
            } else {
                missingWeekStarts.append(weekStart)
            }
        }

        var completedWeeks = loaded.count
        await publishProgress(force: true, completedWeeks: completedWeeks)

        let batchSize = 4
        var failedWeeks = 0

        await withTaskGroup(of: TimetableWeekLoadOutcome.self) { group in
            var nextMissingIndex = 0
            let initialCount = min(batchSize, missingWeekStarts.count)

            for _ in 0..<initialCount {
                let weekStart = missingWeekStarts[nextMissingIndex]
                nextMissingIndex += 1
                group.addTask {
                    await self.loadUncachedRawTimetableWithTimeout(
                        weekStart: weekStart,
                        session: session
                    )
                }
            }

            while let outcome = await group.next() {
                completedWeeks += 1

                if let response = outcome.response {
                    loaded.append(LoadedTimetableWeek(weekStart: outcome.weekStart, response: response))
                } else {
                    failedWeeks += 1
                }

                await publishProgress(
                    force: completedWeeks == totalWeeks,
                    completedWeeks: completedWeeks
                )

                if nextMissingIndex < missingWeekStarts.count {
                    let weekStart = missingWeekStarts[nextMissingIndex]
                    nextMissingIndex += 1
                    group.addTask {
                        await self.loadUncachedRawTimetableWithTimeout(
                            weekStart: weekStart,
                            session: session
                        )
                    }
                }
            }
        }

        return TermTimetableLoadResult(
            responses: loaded
                .sorted { $0.weekStart < $1.weekStart }
                .map(\.response),
            loadedWeeks: loaded.count,
            totalWeeks: totalWeeks,
            failedWeeks: failedWeeks
        )
    }

    private func loadUncachedRawTimetableWithTimeout(
        weekStart: Date,
        session: StoredSession
    ) async -> TimetableWeekLoadOutcome {
        let requestContext = context(for: session)
        do {
            let response = try await withThrowingTaskGroup(of: TimetableResponse.self) { group in
                group.addTask {
                    try await self.fetchTimetable(session: session, weekStart: weekStart)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: self.timetableFetchTimeoutNanoseconds)
                    throw AbsenceSubjectResolutionError.timetableTimeout
                }

                guard let response = try await group.next() else {
                    throw AbsenceSubjectResolutionError.timetableTimeout
                }

                group.cancelAll()
                return response
            }
            try validate(requestContext)
            try? self.timetableCache.save(response, weekStart: weekStart, scope: SchoolDataScope(session: session))
            return TimetableWeekLoadOutcome(weekStart: weekStart, response: response)
        } catch {
            return TimetableWeekLoadOutcome(weekStart: weekStart, response: nil)
        }
    }

    private func publishNextLessonWidgetSnapshot(for week: TimetableWeek, weekStart: Date, cachedAt: Date? = nil) {
        #if canImport(WidgetKit) && (os(iOS) || os(macOS))
        guard let nextLessonWidgetStore else { return }

        let lessons = NextLessonWidgetSnapshotBuilder.lessons(from: week)
        try? nextLessonWidgetStore.updateLessons(lessons, forWeekStarting: weekStart, cachedAt: cachedAt ?? dateProvider())
        WidgetCenter.shared.reloadTimelines(ofKind: NextLessonWidgetConstants.widgetKind)
        #endif
    }

    private func publishWatchTimetable(for week: TimetableWeek, cachedAt: Date) {
        #if !os(macOS)
        watchSyncService?.update(timetable: WatchPayloadBuilder.timetable(from: week, cachedAt: cachedAt))
        #endif
    }
}

@MainActor
private final class TimetableRequestWaiter {
    var continuation: CheckedContinuation<TimetableResponse, Error>?
    func finish(_ result: Result<TimetableResponse, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

private struct TermTimetableLoadResult {
    let responses: [TimetableResponse]
    let loadedWeeks: Int
    let totalWeeks: Int
    let failedWeeks: Int
}

private struct LoadedTimetableWeek {
    let weekStart: Date
    let response: TimetableResponse
}

private struct TimetableWeekLoadOutcome {
    let weekStart: Date
    let response: TimetableResponse?
}

private enum AbsenceSubjectResolutionError: LocalizedError {
    case noUsableTimetable
    case timetableTimeout

    var errorDescription: String? {
        switch self {
        case .noUsableTimetable:
            return AppL10n.string("absence.subjects.error.noTimetable")
        case .timetableTimeout:
            return AppL10n.string("absence.subjects.error.timeout")
        }
    }
}
