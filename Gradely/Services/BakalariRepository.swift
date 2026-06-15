import Foundation
import GradelyWatchShared
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

final class BakalariRepository {
    private let client: any BakalariClient
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

    init(
        client: any BakalariClient,
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

    func login(schoolURL: String, username: String, password: String) async throws -> StoredSession {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty
        else {
            throw AppError.missingFields
        }

        let baseURL = try SchoolURLNormalizer.normalizedBaseURL(from: schoolURL)
        let response = try await client.login(
            baseURL: baseURL,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        let session = try sessionStore.save(loginResponse: response, baseURL: baseURL)
        watchSyncService?.update(session: session)
        return session
    }

    func logout() throws {
        try sessionStore.clearSession()
        try marksCache.clear()
        try absenceCache.clear()
        try timetableCache.clear()
        try? nextLessonWidgetStore?.clear()
        #if canImport(WidgetKit) && (os(iOS) || os(macOS))
        WidgetCenter.shared.reloadTimelines(ofKind: NextLessonWidgetConstants.widgetKind)
        #endif
        try absenceLessonSelectionStore.clearAll()
        watchSyncService?.publishSignedOut()
    }

    func loadCachedMarks() throws -> CachedMarks? {
        try marksCache.load()
    }

    func loadCachedAbsence() throws -> CachedAbsence? {
        try absenceCache.load()
    }

    /// Cached week for instant/offline display, if it matches the requested week.
    func loadCachedTimetable(weekContaining date: Date) -> TimetableWeek? {
        let monday = TimetableDates.monday(of: date)
        guard let cached = try? timetableCache.load(weekStart: monday) else { return nil }
        let week = TimetableMapper.makeWeek(from: cached.response, weekStart: monday)
        publishNextLessonWidgetSnapshot(for: week, weekStart: monday)
        publishWatchTimetable(for: week, cachedAt: cached.cachedAt)
        return week
    }

    /// Fetches and denormalizes the timetable for the week containing `date`, caching the raw response.
    func loadTimetable(weekContaining date: Date) async throws -> TimetableWeek {
        let monday = TimetableDates.monday(of: date)
        let session = try await validSession()
        let response = try await client.fetchTimetable(
            baseURL: session.baseURL,
            accessToken: session.accessToken,
            date: monday
        )
        try? timetableCache.save(response, weekStart: monday)
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

        let response: TimetableResponse
        if let cached = try? timetableCache.load(weekStart: weekStart) {
            response = cached.response
        } else {
            response = try await client.fetchTimetable(
                baseURL: session.baseURL,
                accessToken: session.accessToken,
                date: weekStart
            )
            try? timetableCache.save(response, weekStart: weekStart)
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
        guard let user = try? await client.fetchUser(baseURL: session.baseURL, accessToken: session.accessToken) else {
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
            try marksCache.clear()
        }

        let session = try await validSession()
        let marksResponse = try await client.fetchMarks(
            baseURL: session.baseURL,
            accessToken: session.accessToken
        )
        try marksCache.save(marksResponse)

        async let absenceResponse = optionalAbsenceResponse(baseURL: session.baseURL, accessToken: session.accessToken)
        async let user = optionalUser(baseURL: session.baseURL, accessToken: session.accessToken)

        let absence = await absenceResponse
        if let absence {
            try? absenceCache.save(absence)
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
            try absenceCache.clear()
        }

        let session = try await validSession()
        async let user = optionalUser(baseURL: session.baseURL, accessToken: session.accessToken)

        let response = try await client.fetchAbsences(
            baseURL: session.baseURL,
            accessToken: session.accessToken
        )
        try? absenceCache.save(response)

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
        let predictedSubject = try await client.predictSubject(
            baseURL: session.baseURL,
            accessToken: session.accessToken,
            subject: subject,
            markText: markText,
            weight: weight
        )
        return GradeMath.parseAverageText(predictedSubject.averageText)
    }

    func validSession() async throws -> StoredSession {
        guard let session = try sessionStore.loadSession() else {
            throw AppError.notLoggedIn
        }

        guard session.isExpired else { return session }

        let response = try await client.refreshToken(
            baseURL: session.baseURL,
            refreshToken: session.refreshToken
        )
        let refreshedSession = try sessionStore.save(refreshedResponse: response, currentBaseURL: session.baseURL)
        watchSyncService?.update(session: refreshedSession)
        return refreshedSession
    }

    private func optionalAbsenceResponse(baseURL: URL, accessToken: String) async -> AbsenceResponse? {
        do {
            return try await client.fetchAbsences(baseURL: baseURL, accessToken: accessToken)
        } catch {
            return nil
        }
    }

    private func optionalUser(baseURL: URL, accessToken: String) async -> UserResponse? {
        try? await client.fetchUser(baseURL: baseURL, accessToken: accessToken)
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
        if let cached = try? marksCache.load() {
            return cached.marksResponse
        }

        let response = try await client.fetchMarks(
            baseURL: session.baseURL,
            accessToken: session.accessToken
        )
        try? marksCache.save(response)
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
            if let cached = try? timetableCache.load(weekStart: weekStart) {
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
                    try await self.client.fetchTimetable(
                        baseURL: session.baseURL,
                        accessToken: session.accessToken,
                        date: weekStart
                    )
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
            try? self.timetableCache.save(response, weekStart: weekStart)
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
        watchSyncService?.update(timetable: WatchPayloadBuilder.timetable(from: week, cachedAt: cachedAt))
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
