import Foundation

struct AppEnvironment {
    let repository: BakalariRepository

    static func live() -> AppEnvironment {
        let marksCache: any MarksCaching = (try? MarksCache()) ?? InMemoryMarksCache()
        let timetableCache: any TimetableCaching = (try? TimetableCache()) ?? InMemoryTimetableCache()
        return AppEnvironment(
            repository: BakalariRepository(
                client: DemoAwareBakalariClient(liveClient: URLSessionBakalariClient()),
                sessionStore: SessionStore(),
                marksCache: marksCache,
                timetableCache: timetableCache
            )
        )
    }

    static func current() -> AppEnvironment {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTestingMockAPI") else {
            return live()
        }

        let preloadedSession = arguments.contains("-uiTestingLoggedIn") ? PreviewData.expiredSession : nil
        let store = InMemorySessionStore(session: preloadedSession)
        let cache = InMemoryMarksCache(
            cachedMarks: arguments.contains("-uiTestingCachedMarks")
                ? CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date())
                : nil
        )

        return AppEnvironment(
            repository: BakalariRepository(
                client: MockBakalariClient(
                    refreshedResult: LoginResponse(
                        accessToken: "mock-refreshed-access",
                        refreshToken: "mock-refreshed-refresh",
                        tokenType: "Bearer",
                        expiresIn: 3600,
                        apiVersion: nil,
                        appVersion: nil,
                        userID: "mock-user"
                    )
                ),
                sessionStore: store,
                marksCache: cache
            )
        )
    }
}
