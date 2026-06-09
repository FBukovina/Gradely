import Foundation

struct AppEnvironment {
    let repository: BakalariRepository
    let stravaCZRepository: StravaCZRepository
    let schoolDirectoryProvider: any SchoolDirectoryProviding
    let supportTipProvider: any SupportTipProviding

    init(
        repository: BakalariRepository,
        stravaCZRepository: StravaCZRepository = AppEnvironment.makeMockStravaCZRepository(),
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        supportTipProvider: any SupportTipProviding = MockSupportTipService()
    ) {
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.supportTipProvider = supportTipProvider
    }

    static func live() -> AppEnvironment {
        let marksCache: any MarksCaching = (try? MarksCache()) ?? InMemoryMarksCache()
        let absenceCache: any AbsenceCaching = (try? AbsenceCache()) ?? InMemoryAbsenceCache()
        let timetableCache: any TimetableCaching = (try? TimetableCache()) ?? InMemoryTimetableCache()
        let absenceLessonSelectionStore: any AbsenceLessonSelectionStoring = (try? AbsenceLessonSelectionStore()) ?? InMemoryAbsenceLessonSelectionStore()
        let schoolDirectoryCache: any SchoolDirectoryCaching = (try? SchoolDirectoryCache()) ?? InMemorySchoolDirectoryCache()
        let schoolDirectoryProvider = URLSessionSchoolDirectoryProvider(cache: schoolDirectoryCache)
        return AppEnvironment(
            repository: BakalariRepository(
                client: DemoAwareBakalariClient(liveClient: URLSessionBakalariClient()),
                sessionStore: SessionStore(),
                marksCache: marksCache,
                absenceCache: absenceCache,
                timetableCache: timetableCache,
                nextLessonWidgetStore: NextLessonWidgetStore(),
                absenceLessonSelectionStore: absenceLessonSelectionStore,
                schoolDirectoryProvider: schoolDirectoryProvider
            ),
            stravaCZRepository: StravaCZRepository(
                client: URLSessionStravaCZClient(),
                sessionStore: StravaCZSessionStore(),
                menuCache: (try? StravaCZMenuCache()) ?? InMemoryStravaCZMenuCache()
            ),
            schoolDirectoryProvider: schoolDirectoryProvider,
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
        let schoolDirectoryProvider = MockSchoolDirectoryProvider(refreshResult: PreviewData.schoolDirectorySchools)

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
                marksCache: cache,
                schoolDirectoryProvider: schoolDirectoryProvider
            ),
            stravaCZRepository: makeMockStravaCZRepository(
                session: arguments.contains("-uiTestingStravaCZLoggedIn") ? PreviewData.stravaCZSession : nil
            ),
            schoolDirectoryProvider: schoolDirectoryProvider,
            supportTipProvider: MockSupportTipService()
        )
    }

    static func makeMockStravaCZRepository(session: StravaCZStoredSession? = nil) -> StravaCZRepository {
        let menu = session == nil
            ? nil
            : CachedStravaCZMenu(menu: StravaCZMenu.make(from: PreviewData.stravaCZMenuResponse), cachedAt: Date())

        return StravaCZRepository(
            client: MockStravaCZClient(),
            sessionStore: InMemoryStravaCZSessionStore(session: session),
            menuCache: InMemoryStravaCZMenuCache(cachedMenu: menu)
        )
    }
}
