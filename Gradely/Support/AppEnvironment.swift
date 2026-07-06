import Foundation

struct AppEnvironment {
    let repository: SchoolRepository
    let stravaCZRepository: StravaCZRepository
    let schoolDirectoryProvider: any SchoolDirectoryProviding
    let supportTipProvider: any SupportTipProviding
    let watchSyncService: (any WatchSyncing)?
    let gradeyAuthClient: any GradeyAuthClient
    let linkedAccountRepository: LinkedAccountRepository
    let historyRepository: GradeyHistoryRepository
    let devicePushTokenClient: any DevicePushTokenClient
    let notificationSettingsStore: MarkNotificationSettingsStore
    let requiresGradeyID: Bool

    init(
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository = AppEnvironment.makeMockStravaCZRepository(),
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        supportTipProvider: any SupportTipProviding = MockSupportTipService(),
        watchSyncService: (any WatchSyncing)? = nil,
        gradeyAuthClient: any GradeyAuthClient = MockGradeyAuthClient(),
        linkedAccountRepository: LinkedAccountRepository? = nil,
        historyRepository: GradeyHistoryRepository? = nil,
        devicePushTokenClient: any DevicePushTokenClient = MockDevicePushTokenClient(),
        notificationSettingsStore: MarkNotificationSettingsStore = MarkNotificationSettingsStore(userDefaults: .standard),
        requiresGradeyID: Bool = false
    ) {
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.supportTipProvider = supportTipProvider
        self.watchSyncService = watchSyncService
        self.gradeyAuthClient = gradeyAuthClient
        self.devicePushTokenClient = devicePushTokenClient
        self.notificationSettingsStore = notificationSettingsStore
        self.requiresGradeyID = requiresGradeyID
        self.linkedAccountRepository = linkedAccountRepository ?? LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: .standard),
            client: MockLinkedAccountClient(),
            authClient: gradeyAuthClient
        )
        self.historyRepository = historyRepository ?? GradeyHistoryRepository(
            client: MockGradeyHistoryClient(),
            authClient: gradeyAuthClient
        )
    }

    static func live() -> AppEnvironment {
        let marksCache: any MarksCaching = (try? MarksCache()) ?? InMemoryMarksCache()
        let absenceCache: any AbsenceCaching = (try? AbsenceCache()) ?? InMemoryAbsenceCache()
        let timetableCache: any TimetableCaching = (try? TimetableCache()) ?? InMemoryTimetableCache()
        let absenceLessonSelectionStore: any AbsenceLessonSelectionStoring = (try? AbsenceLessonSelectionStore()) ?? InMemoryAbsenceLessonSelectionStore()
        let schoolDirectoryCache: any SchoolDirectoryCaching = (try? SchoolDirectoryCache()) ?? InMemorySchoolDirectoryCache()
        let schoolDirectoryProvider = URLSessionSchoolDirectoryProvider(cache: schoolDirectoryCache)
        #if os(macOS)
        let watchSyncService: (any WatchSyncing)? = nil
        let nextLessonWidgetStore: (any NextLessonWidgetStoring)? = NextLessonWidgetStore()
        let supportTipProvider: any SupportTipProviding = StoreKitSupportTipService()
        #else
        let watchSyncService: (any WatchSyncing)? = LiveWatchSyncService()
        let nextLessonWidgetStore: (any NextLessonWidgetStoring)? = NextLessonWidgetStore()
        let supportTipProvider: any SupportTipProviding = RevenueCatSupportTipService()
        #endif
        let gradeyAuthClient = SupabaseGradeyAuthClient()
        let devicePushTokenClient = SupabaseDevicePushTokenClient()
        let notificationSettingsStore = MarkNotificationSettingsStore()
        let linkedAccountRepository = LinkedAccountRepository(
            client: SupabaseLinkedAccountClient(),
            authClient: gradeyAuthClient
        )
        let historyRepository = GradeyHistoryRepository(
            client: SupabaseGradeyHistoryClient(),
            authClient: gradeyAuthClient
        )

        return AppEnvironment(
            repository: SchoolRepository(
                client: DemoAwareBakalariClient(liveClient: URLSessionBakalariClient()),
                sessionStore: SessionStore(),
                marksCache: marksCache,
                absenceCache: absenceCache,
                timetableCache: timetableCache,
                nextLessonWidgetStore: nextLessonWidgetStore,
                absenceLessonSelectionStore: absenceLessonSelectionStore,
                schoolDirectoryProvider: schoolDirectoryProvider,
                watchSyncService: watchSyncService
            ),
            stravaCZRepository: StravaCZRepository(
                client: URLSessionStravaCZClient(),
                sessionStore: StravaCZSessionStore(),
                menuCache: (try? StravaCZMenuCache()) ?? InMemoryStravaCZMenuCache()
            ),
            schoolDirectoryProvider: schoolDirectoryProvider,
            supportTipProvider: supportTipProvider,
            watchSyncService: watchSyncService,
            gradeyAuthClient: gradeyAuthClient,
            linkedAccountRepository: linkedAccountRepository,
            historyRepository: historyRepository,
            devicePushTokenClient: devicePushTokenClient,
            notificationSettingsStore: notificationSettingsStore,
            requiresGradeyID: true
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

        let gradeyAuthClient = MockGradeyAuthClient(
            session: arguments.contains("-uiTestingGradeyIDSignedOut") ? nil : PreviewData.gradeyAuthSession
        )
        let linkedAccountRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: .standard),
            client: MockLinkedAccountClient(),
            authClient: gradeyAuthClient
        )
        linkedAccountRepository.clearLocalAccounts()
        if arguments.contains("-uiTestingLinkedAccounts") {
            linkedAccountRepository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        }
        let notificationSettingsStore = MarkNotificationSettingsStore(userDefaults: .standard)
        notificationSettingsStore.preferences = .default

        return AppEnvironment(
            repository: SchoolRepository(
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
            supportTipProvider: MockSupportTipService(),
            gradeyAuthClient: gradeyAuthClient,
            linkedAccountRepository: linkedAccountRepository,
            historyRepository: GradeyHistoryRepository(
                client: MockGradeyHistoryClient(response: PreviewData.gradeHistoryResponse),
                authClient: gradeyAuthClient
            ),
            devicePushTokenClient: MockDevicePushTokenClient(),
            notificationSettingsStore: notificationSettingsStore,
            requiresGradeyID: arguments.contains("-uiTestingRequiresGradeyID")
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
