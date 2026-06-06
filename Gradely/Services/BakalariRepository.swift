import Foundation

struct DashboardData: Equatable {
    let marksResponse: MarksResponse
    let absencesPerSubject: [AbsencePerSubject]
    let user: UserResponse?
}

struct AbsenceData: Equatable {
    let response: AbsenceResponse
    let absencesPerSubject: [AbsencePerSubject]
    let user: UserResponse?
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
    private let dateProvider: () -> Date

    init(
        client: any BakalariClient,
        sessionStore: any SessionStoring,
        marksCache: any MarksCaching,
        absenceCache: any AbsenceCaching = InMemoryAbsenceCache(),
        timetableCache: any TimetableCaching = InMemoryTimetableCache(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.sessionStore = sessionStore
        self.marksCache = marksCache
        self.absenceCache = absenceCache
        self.timetableCache = timetableCache
        self.dateProvider = dateProvider
    }

    func bootstrapSession() throws -> StoredSession? {
        try sessionStore.loadSession()
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
        return try sessionStore.save(loginResponse: response, baseURL: baseURL)
    }

    func logout() throws {
        try sessionStore.clearSession()
        try marksCache.clear()
        try absenceCache.clear()
        try timetableCache.clear()
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
        return TimetableMapper.makeWeek(from: cached.response, weekStart: monday)
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
        return TimetableMapper.makeWeek(from: response, weekStart: monday)
    }

    /// Best-effort current user, used to populate the account menu on tabs other than Marks.
    func loadUser() async -> UserResponse? {
        guard let session = try? await validSession() else { return nil }
        return try? await client.fetchUser(baseURL: session.baseURL, accessToken: session.accessToken)
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

        return DashboardData(
            marksResponse: marksResponse,
            absencesPerSubject: absence?.absencesPerSubject ?? [],
            user: await user
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

        let resolvedSubjects = await resolvedSubjectAbsences(
            response: response,
            session: session
        )

        return AbsenceData(
            response: response,
            absencesPerSubject: resolvedSubjects,
            user: await user
        )
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
        return try sessionStore.save(refreshedResponse: response, currentBaseURL: session.baseURL)
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

    private func resolvedSubjectAbsences(
        response: AbsenceResponse,
        session: StoredSession
    ) async -> [AbsencePerSubject] {
        guard response.absencesPerSubject.isEmpty else { return response.absencesPerSubject }
        guard !response.absences.isEmpty else { return [] }

        do {
            let marksResponse = try await marksResponseForAbsenceFallback(session: session)
            let term = AbsenceSubjectFallback.currentTerm(containing: dateProvider())
            let timetables = try await loadTermTimetableResponses(
                weekStarts: term.weekStarts,
                session: session
            )

            return AbsenceSubjectFallback.makeAbsences(
                from: response,
                timetableResponses: timetables,
                subjects: marksResponse.subjects,
                validDateRange: term.start...term.end
            )
        } catch {
            return []
        }
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

    private func loadTermTimetableResponses(
        weekStarts: [Date],
        session: StoredSession
    ) async throws -> [TimetableResponse] {
        let batchSize = 4
        var responses: [TimetableResponse] = []
        var batchStart = 0

        while batchStart < weekStarts.count {
            let batchEnd = min(batchStart + batchSize, weekStarts.count)

            for weekStart in weekStarts[batchStart..<batchEnd] {
                responses.append(
                    try await loadRawTimetable(
                        weekStart: weekStart,
                        session: session
                    )
                )
            }

            batchStart = batchEnd
            await Task.yield()
        }

        return responses
    }

    private func loadRawTimetable(
        weekStart: Date,
        session: StoredSession
    ) async throws -> TimetableResponse {
        if let cached = try? timetableCache.load(weekStart: weekStart) {
            return cached.response
        }

        let response = try await client.fetchTimetable(
            baseURL: session.baseURL,
            accessToken: session.accessToken,
            date: weekStart
        )
        try? timetableCache.save(response, weekStart: weekStart)
        return response
    }
}
