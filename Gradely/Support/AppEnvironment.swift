import Foundation

struct AppEnvironment {
    let repository: BakalariRepository
    let schoolDirectoryProvider: any SchoolDirectoryProviding
    let supportTipProvider: any SupportTipProviding

    init(
        repository: BakalariRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        supportTipProvider: any SupportTipProviding = MockSupportTipService()
    ) {
        self.repository = repository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.supportTipProvider = supportTipProvider
    }

    static func live() -> AppEnvironment {
        let marksCache: any MarksCaching = (try? MarksCache()) ?? InMemoryMarksCache()
        let absenceCache: any AbsenceCaching = (try? AbsenceCache()) ?? InMemoryAbsenceCache()
        let timetableCache: any TimetableCaching = (try? TimetableCache()) ?? InMemoryTimetableCache()
        let absenceLessonSelectionStore: any AbsenceLessonSelectionStoring = (try? AbsenceLessonSelectionStore()) ?? InMemoryAbsenceLessonSelectionStore()
        let schoolDirectoryCache: any SchoolDirectoryCaching = (try? SchoolDirectoryCache()) ?? InMemorySchoolDirectoryCache()
        return AppEnvironment(
            repository: BakalariRepository(
                client: DemoAwareBakalariClient(liveClient: URLSessionBakalariClient()),
                sessionStore: SessionStore(),
                marksCache: marksCache,
                absenceCache: absenceCache,
                timetableCache: timetableCache,
                absenceLessonSelectionStore: absenceLessonSelectionStore
            ),
            schoolDirectoryProvider: URLSessionSchoolDirectoryProvider(cache: schoolDirectoryCache),
            supportTipProvider: RevenueCatSupportTipService()
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
        let useLargeSubjectAbsenceMock = arguments.contains("-uiTestingLargeAbsenceSubjects")
        let useManualSubjectAbsenceMock = arguments.contains("-uiTestingManualSubjectAbsence")
        let useEmptySubjectAbsenceMock = arguments.contains("-uiTestingEmptySubjectAbsence")

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
                    ),
                    absenceResult: useLargeSubjectAbsenceMock
                        ? PreviewData.largeSubjectAbsenceResponseWithoutSubjectRows
                        : (
                            useManualSubjectAbsenceMock
                                ? PreviewData.manualSubjectAbsenceResponseWithoutSubjectRows
                                : (useEmptySubjectAbsenceMock ? PreviewData.absenceResponseWithoutSubjectRows : PreviewData.absenceResponse)
                        ),
                    timetableResult: useLargeSubjectAbsenceMock
                        ? PreviewData.largeSubjectTimetableResponse
                        : (useManualSubjectAbsenceMock ? PreviewData.manualSubjectTimetableResponse : PreviewData.timetableResponse)
                ),
                sessionStore: store,
                marksCache: cache
            ),
            schoolDirectoryProvider: MockSchoolDirectoryProvider(refreshResult: PreviewData.schoolDirectorySchools),
            supportTipProvider: MockSupportTipService()
        )
    }
}
