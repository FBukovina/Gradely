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
                return String(localized: "error.notLoggedIn")
            case .missingFields:
                return String(localized: "error.missingFields")
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

        switch provider {
        case .bakalari:
            let baseURL = try SchoolURLNormalizer.normalizedBaseURL(from: schoolURL)
            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await client.login(
                baseURL: baseURL,
                username: trimmedUsername,
                password: password
            )
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
            return try await mapEduPageLoginResult(
                eduPageClient.beginLogin(
                    baseURL: baseURL,
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                ),
                baseURL: baseURL
            )
        }
    }

    func completeEduPageTwoFactor(code: String) async throws -> SchoolLoginStep {
        guard let baseURL = pendingEduPageBaseURL else {
            throw SchoolAuthenticationError.twoFactorRequired
        }
        return try await mapEduPageLoginResult(
            eduPageClient.completeTwoFactor(code: code),
            baseURL: baseURL
        )
    }

    func completeApprovedEduPageTwoFactor() async throws -> SchoolLoginStep {
        guard let baseURL = pendingEduPageBaseURL else {
            throw SchoolAuthenticationError.twoFactorRequired
        }
        return try await mapEduPageLoginResult(
            eduPageClient.completeApprovedTwoFactor(),
            baseURL: baseURL
        )
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
        let data = try await eduPageClient.selectStudent(studentID)
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
        session.eduPage = try await eduPageClient.switchStudent(studentID, in: eduPage, baseURL: session.baseURL)
        session.accessToken = session.eduPage?.sessionID ?? session.accessToken
        try sessionStore.save(session: session)
        let scope = SchoolDataScope(session: session)
        try marksCache.clear(scope: scope)
        try absenceCache.clear(scope: scope)
        try timetableCache.clear(scope: scope)
        try? nextLessonWidgetStore?.clear()
        watchSyncService?.update(session: session)
    }

    func activateLinkedSchoolAccount(_ activation: LinkedSchoolAccountActivation) throws -> StoredSession {
        let session = activation.makeStoredSession()
        try sessionStore.save(session: session)
        watchSyncService?.update(session: session)
        NotificationCenter.default.post(name: .gradelySchoolAccountDidChange, object: nil)
        return session
    }

    /// Keeps a freshly authenticated local provider session associated with its
    /// existing Gradey cloud account after a reconnect.
    func associateCurrentSession(with account: LinkedAccount) throws {
        guard var session = try sessionStore.loadSession(),
              account.provider == LinkedAccountProvider(schoolProvider: session.provider)
        else {
            throw AppError.notLoggedIn
        }

        session.linkedAccountID = account.id
        session.linkedAccountDisplayName = account.displayName
        session.linkedAccountSchoolName = account.schoolName
        try sessionStore.save(session: session)
        watchSyncService?.update(session: session)
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
            try marksCache.clear(scope: scope)
            try absenceCache.clear(scope: scope)
            try timetableCache.clear(scope: scope)
        } else {
            try marksCache.clear()
            try absenceCache.clear()
            try timetableCache.clear()
        }
        try absenceLessonSelectionStore.clearAll()
        try? nextLessonWidgetStore?.clear()
    }

    func clearLocalCaches() throws {
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

    /// Cached week for instant/offline display, if it matches the requested week.
    func loadCachedTimetable(weekContaining date: Date) -> TimetableWeek? {
        let monday = TimetableDates.monday(of: date)
        let scope = (try? sessionStore.loadSession()).map(SchoolDataScope.init(session:))
        let cached: CachedTimetable?
        if let scope {
            cached = try? timetableCache.load(weekStart: monday, scope: scope)
        } else {
            cached = try? timetableCache.load(weekStart: monday)
        }
        guard let cached else { return nil }
        let week = TimetableMapper.makeWeek(from: cached.response, weekStart: monday)
        publishNextLessonWidgetSnapshot(for: week, weekStart: monday)
        publishWatchTimetable(for: week, cachedAt: cached.cachedAt)
        return week
    }

    /// Fetches and denormalizes the timetable for the week containing `date`, caching the raw response.
    func loadTimetable(weekContaining date: Date) async throws -> TimetableWeek {
        let monday = TimetableDates.monday(of: date)
        let session = try await validSession()
        let response = try await fetchTimetable(session: session, weekStart: monday)
        try? timetableCache.save(response, weekStart: monday, scope: SchoolDataScope(session: session))
        let week = TimetableMapper.makeWeek(from: response, weekStart: monday)
        publishNextLessonWidgetSnapshot(for: week, weekStart: monday)
        publishWatchTimetable(for: week, cachedAt: dateProvider())
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
        guard let user = try? await fetchUser(session: session) else {
            return nil
        }
        let resolved = resolvedUser(user, session: session)
        if let resolved {
            watchSyncService?.update(user: resolved)
        }
        return resolved
    }

    func loadDashboard(forceRefresh: Bool = false) async throws -> DashboardData {
        if forceRefresh {
            if let session = try? sessionStore.loadSession() {
                try marksCache.clear(scope: SchoolDataScope(session: session))
            } else {
                try marksCache.clear()
            }
        }

        let session = try await validSession()
        let marksResponse = try await fetchMarks(session: session)
        let scope = SchoolDataScope(session: session)
        try marksCache.save(marksResponse, scope: scope)

        async let absenceResponse = optionalAbsenceResponse(session: session)
        async let user = optionalUser(session: session)

        let absence = await absenceResponse
        if let absence {
            try? absenceCache.save(absence, scope: scope)
        }

        let resolvedDashboardUser = resolvedUser(await user, session: session)
        if let resolvedDashboardUser {
            watchSyncService?.update(user: resolvedDashboardUser)
        }

        return DashboardData(
            marksResponse: marksResponse,
            absencesPerSubject: absence?.absencesPerSubject ?? [],
            user: resolvedDashboardUser
        )
    }

    func loadAbsence(forceRefresh: Bool = false) async throws -> AbsenceData {
        if forceRefresh {
            if let session = try? sessionStore.loadSession() {
                try absenceCache.clear(scope: SchoolDataScope(session: session))
            } else {
                try absenceCache.clear()
            }
        }

        let session = try await validSession()
        let scope = SchoolDataScope(session: session)
        async let user = optionalUser(session: session)

        let response = try await fetchAbsences(session: session)
        try? absenceCache.save(response, scope: scope)

        let resolvedAbsenceUser = resolvedUser(await user, session: session)
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
        let warning = hasPartialTimetable ? String(localized: "absence.subjects.partial.warning") : nil

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
        if let bakalariRefreshTask {
            return try await bakalariRefreshTask.value
        }

        let task = Task { try await performBakalariRefresh(force: force) }
        bakalariRefreshTask = task
        defer { bakalariRefreshTask = nil }
        return try await task.value
    }

    /// Refreshes the Bakaláři access token, re-loading the session first so a
    /// caller arriving just after another refresh finished does not redeem an
    /// already-rotated token. If the refresh token is rejected ("token already
    /// redeemed"), falls back to a full re-login with the stored credentials so
    /// the user is never forced to sign in again manually.
    private func performBakalariRefresh(force: Bool) async throws -> StoredSession {
        guard let session = try sessionStore.loadSession() else {
            throw AppError.notLoggedIn
        }
        guard session.provider == .bakalari else { return session }
        guard force || session.isExpired else { return session }

        do {
            let response = try await client.refreshToken(
                baseURL: session.baseURL,
                refreshToken: session.refreshToken
            )
            return try persistBakalariSession(
                from: response,
                baseURL: session.baseURL,
                credentials: session.bakalari,
                metadataFrom: session
            )
        } catch {
            guard isRefreshTokenRejected(error), let credentials = session.bakalari else {
                throw error
            }
            let response = try await client.login(
                baseURL: session.baseURL,
                username: credentials.username,
                password: credentials.password
            )
            return try persistBakalariSession(
                from: response,
                baseURL: session.baseURL,
                credentials: credentials,
                metadataFrom: session
            )
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
        do {
            return try await operation(session)
        } catch {
            guard session.provider == .bakalari, isAccessTokenRejected(error) else { throw error }
            let refreshed = try await refreshBakalariSession(force: true)
            return try await operation(refreshed)
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

    private func fetchTimetable(session: StoredSession, weekStart: Date) async throws -> TimetableResponse {
        switch session.provider {
        case .bakalari:
            return try await withBakalariRetry(session: session) { current in
                try await self.client.fetchTimetable(
                    baseURL: current.baseURL,
                    accessToken: current.accessToken,
                    date: weekStart
                )
            }
        case .eduPage:
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
        guard let data = stored.eduPage else {
            throw SchoolAuthenticationError.sessionExpired
        }

        do {
            return try await operation(data)
        } catch SchoolAuthenticationError.sessionExpired {
            let refreshed = try await eduPageClient.restore(data, baseURL: stored.baseURL)
            var updated = stored
            updated.accessToken = refreshed.sessionID
            updated.eduPage = refreshed
            try sessionStore.save(session: updated)
            watchSyncService?.update(session: updated)
            return try await operation(refreshed)
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
        let scope = SchoolDataScope(session: session)
        if let cached = try? marksCache.load(scope: scope) {
            return cached.marksResponse
        }

        let response = try await fetchMarks(session: session)
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
            try? self.timetableCache.save(response, weekStart: weekStart, scope: SchoolDataScope(session: session))
            return TimetableWeekLoadOutcome(weekStart: weekStart, response: response)
        } catch {
            return TimetableWeekLoadOutcome(weekStart: weekStart, response: nil)
        }
    }

    private func publishNextLessonWidgetSnapshot(for week: TimetableWeek, weekStart: Date) {
        #if canImport(WidgetKit) && (os(iOS) || os(macOS))
        guard let nextLessonWidgetStore else { return }

        let lessons = NextLessonWidgetSnapshotBuilder.lessons(from: week)
        try? nextLessonWidgetStore.updateLessons(lessons, forWeekStarting: weekStart, cachedAt: dateProvider())
        WidgetCenter.shared.reloadTimelines(ofKind: NextLessonWidgetConstants.widgetKind)
        #endif
    }

    private func publishWatchTimetable(for week: TimetableWeek, cachedAt: Date) {
        #if !os(macOS)
        watchSyncService?.update(timetable: WatchPayloadBuilder.timetable(from: week, cachedAt: cachedAt))
        #endif
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
            return String(localized: "absence.subjects.error.noTimetable")
        case .timetableTimeout:
            return String(localized: "absence.subjects.error.timeout")
        }
    }
}
