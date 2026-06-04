import Foundation

struct DashboardData: Equatable {
    let marksResponse: MarksResponse
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
    private let timetableCache: any TimetableCaching

    init(
        client: any BakalariClient,
        sessionStore: any SessionStoring,
        marksCache: any MarksCaching,
        timetableCache: any TimetableCaching = InMemoryTimetableCache()
    ) {
        self.client = client
        self.sessionStore = sessionStore
        self.marksCache = marksCache
        self.timetableCache = timetableCache
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
        try timetableCache.clear()
    }

    func loadCachedMarks() throws -> CachedMarks? {
        try marksCache.load()
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

        async let absences = optionalAbsences(baseURL: session.baseURL, accessToken: session.accessToken)
        async let user = optionalUser(baseURL: session.baseURL, accessToken: session.accessToken)

        return DashboardData(
            marksResponse: marksResponse,
            absencesPerSubject: await absences,
            user: await user
        )
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

    private func optionalAbsences(baseURL: URL, accessToken: String) async -> [AbsencePerSubject] {
        do {
            return try await client.fetchAbsences(baseURL: baseURL, accessToken: accessToken).absencesPerSubject
        } catch {
            return []
        }
    }

    private func optionalUser(baseURL: URL, accessToken: String) async -> UserResponse? {
        try? await client.fetchUser(baseURL: baseURL, accessToken: accessToken)
    }
}
