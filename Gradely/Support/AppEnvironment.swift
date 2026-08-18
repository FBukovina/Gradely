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
    let gradeyAIClient: any GradeyAIClient
    let gradeyAIContextBuilder: any GradeyAIContextBuilding
    let devicePushTokenClient: any DevicePushTokenClient
    let notificationSettingsStore: MarkNotificationSettingsStore
    let guestModeStore: any GradeyGuestModeStoring
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
        gradeyAIClient: (any GradeyAIClient)? = nil,
        gradeyAIContextBuilder: (any GradeyAIContextBuilding)? = nil,
        devicePushTokenClient: any DevicePushTokenClient = MockDevicePushTokenClient(),
        notificationSettingsStore: MarkNotificationSettingsStore = MarkNotificationSettingsStore(userDefaults: .standard),
        guestModeStore: any GradeyGuestModeStoring = GradeyGuestModeStore(),
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
        self.guestModeStore = guestModeStore
        self.requiresGradeyID = requiresGradeyID
        let resolvedLinkedAccountRepository = linkedAccountRepository ?? LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: .standard),
            client: MockLinkedAccountClient(),
            authClient: gradeyAuthClient
        )
        let resolvedHistoryRepository = historyRepository ?? GradeyHistoryRepository(
            client: MockGradeyHistoryClient(),
            authClient: gradeyAuthClient
        )
        self.linkedAccountRepository = resolvedLinkedAccountRepository
        self.historyRepository = resolvedHistoryRepository
        self.gradeyAIClient = gradeyAIClient ?? MockGradeyAIClient()
        self.gradeyAIContextBuilder = gradeyAIContextBuilder ?? GradeyAIContextBuilder(
            repository: repository,
            historyRepository: resolvedHistoryRepository
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
        let repository = SchoolRepository(
            client: DemoAwareBakalariClient(liveClient: URLSessionBakalariClient()),
            sessionStore: SessionStore(),
            marksCache: marksCache,
            absenceCache: absenceCache,
            timetableCache: timetableCache,
            nextLessonWidgetStore: nextLessonWidgetStore,
            absenceLessonSelectionStore: absenceLessonSelectionStore,
            schoolDirectoryProvider: schoolDirectoryProvider,
            watchSyncService: watchSyncService
        )

        return AppEnvironment(
            repository: repository,
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
            gradeyAIClient: FirebaseGradeyAIClient(),
            gradeyAIContextBuilder: GradeyAIContextBuilder(
                repository: repository,
                historyRepository: historyRepository
            ),
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
        let useGradeyAIQuotaMock = arguments.contains("-uiTestingGradeyAIQuota")
        let useGradeyAIDisabledMock = arguments.contains("-uiTestingGradeyAIDisabled")
        let schoolDirectorySchools = arguments.contains("-uiTestingBroadSchoolSearch")
            ? PreviewData.broadSchoolDirectorySearchFixture
            : PreviewData.schoolDirectorySchools
        let schoolDirectoryProvider = MockSchoolDirectoryProvider(refreshResult: schoolDirectorySchools)
        let eduPageClient = UITestEduPageClient(
            requiresTwoFactor: arguments.contains("-uiTestingEduPageTwoFactor"),
            requiresStudentSelection: arguments.contains("-uiTestingEduPageChildSelection")
        )

        var gradeyUITestSession = arguments.contains("-uiTestingGradeyIDSignedOut")
            ? nil
            : PreviewData.gradeyAuthSession
        if arguments.contains("-uiTestingMissingGradeyName"),
           var namelessSession = gradeyUITestSession {
            namelessSession.account.fullName = nil
            gradeyUITestSession = namelessSession
        }
        let gradeyAuthClient = MockGradeyAuthClient(
            session: gradeyUITestSession,
            updateFullNameError: arguments.contains("-uiTestingGradeyNameUpdateFailure")
                ? GradeyAuthError.server("Mock name update failed")
                : nil
        )
        let linkedAccountRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: .standard),
            client: MockLinkedAccountClient(
                schoolLinkError: arguments.contains("-uiTestingSchoolCloudLinkFailure")
                    ? GradeyAuthError.server("Mock school cloud link failed")
                    : nil,
                stravaCZLinkError: arguments.contains("-uiTestingMealsCloudLinkFailure")
                    ? GradeyAuthError.server("Mock meals cloud link failed")
                    : nil
            ),
            authClient: gradeyAuthClient
        )
        linkedAccountRepository.clearLocalAccounts()
        if arguments.contains("-uiTestingLinkedAccounts") {
            var account = PreviewData.linkedSchoolAccount
            if arguments.contains("-uiTestingLinkedAccountActionRequired") {
                account.status = .actionRequired
                account.actionRequiredReason = "Provider credentials expired"
            }
            linkedAccountRepository.replaceLocalAccounts([account])
            if var session = try? store.loadSession() {
                session.bakalari = BakalariCredentials(
                    username: DemoAccount.username,
                    password: DemoAccount.password
                )
                session.linkedAccountID = account.id
                session.linkedAccountDisplayName = account.displayName
                session.linkedAccountSchoolName = account.schoolName
                try? store.save(session: session)
            }
        }
        let notificationSettingsStore = MarkNotificationSettingsStore(userDefaults: .standard)
        var notificationPreferences = NotificationPreferences.default
        if arguments.contains("-uiTestingQuietHoursEnabled") {
            notificationPreferences.quietHoursEnabled = true
        }
        notificationSettingsStore.preferences = notificationPreferences
        let mockAccountSettingsClient = MockDevicePushTokenClient(
            accountSettings: GradeyAccountSettingsSnapshot(
                activeSchoolAccountID: linkedAccountRepository.loadAccounts().first(where: { $0.provider.isSchoolProvider })?.id,
                linkedAccounts: linkedAccountRepository.loadAccounts(),
                notificationPreferences: notificationSettingsStore.preferences
            ),
            fetchError: arguments.contains("-uiTestingAccountSettingsOffline")
                ? URLError(.notConnectedToInternet)
                : nil
        )
        let guestModeStore = GradeyGuestModeStore()
        if arguments.contains("-uiTestingResetGuestMode") {
            guestModeStore.isEnabled = false
        }
        let gradeyAISnapshot = GradeyAIContextSnapshot(
            schoolScope: "school_ui_test",
            generatedAt: Date(),
            isStale: false,
            unavailableSections: [.trends, .timetable],
            subjects: GradeyAIContextBuilder.makeSubjects(from: PreviewData.subjects),
            trends: [],
            timetable: []
        )

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
                eduPageClient: eduPageClient,
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
            gradeyAIClient: MockGradeyAIClient(
                status: GradeyAIStatus(
                    enabled: !useGradeyAIDisabledMock,
                    consentRequired: arguments.contains("-uiTestingGradeyAIConsentRequired"),
                    termsVersion: "2026-07-10.v1",
                    dailyLimit: useGradeyAIQuotaMock ? 5 : 30,
                    dailyUsed: useGradeyAIQuotaMock ? 2 : 0,
                    remaining: useGradeyAIQuotaMock ? 3 : 30,
                    resetAt: useGradeyAIQuotaMock ? Date().addingTimeInterval(3_600) : nil
                )
            ),
            gradeyAIContextBuilder: MockGradeyAIContextBuilder(
                snapshot: gradeyAISnapshot,
                refreshSnapshot: gradeyAISnapshot
            ),
            devicePushTokenClient: mockAccountSettingsClient,
            notificationSettingsStore: notificationSettingsStore,
            guestModeStore: guestModeStore,
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

private final class UITestEduPageClient: EduPageClient, @unchecked Sendable {
    private let requiresTwoFactor: Bool
    private let requiresStudentSelection: Bool

    private let students = [
        SchoolStudentProfile(id: "Student1", fullName: "Test Student", classID: "1", className: "1.A"),
        SchoolStudentProfile(id: "Student2", fullName: "Second Student", classID: "2", className: "2.B")
    ]

    init(requiresTwoFactor: Bool, requiresStudentSelection: Bool) {
        self.requiresTwoFactor = requiresTwoFactor
        self.requiresStudentSelection = requiresStudentSelection
    }

    func beginLogin(baseURL: URL, username: String, password: String) async throws -> EduPageLoginResult {
        if requiresTwoFactor {
            return .twoFactor(EduPageTwoFactorPrompt())
        }
        if requiresStudentSelection {
            return .studentSelection(students)
        }
        return .authenticated(sessionData(activeStudent: students[0]))
    }

    func completeTwoFactor(code: String) async throws -> EduPageLoginResult {
        if requiresStudentSelection {
            return .studentSelection(students)
        }
        return .authenticated(sessionData(activeStudent: students[0]))
    }

    func completeApprovedTwoFactor() async throws -> EduPageLoginResult {
        try await completeTwoFactor(code: "approved")
    }

    func isTwoFactorConfirmed() async throws -> Bool { true }

    func resendTwoFactorNotification() async throws {}

    func selectStudent(_ studentID: String) async throws -> EduPageSessionData {
        guard let student = students.first(where: { $0.id == studentID }) else {
            throw SchoolAuthenticationError.invalidStudent
        }
        return sessionData(activeStudent: student)
    }

    func switchStudent(
        _ studentID: String,
        in session: EduPageSessionData,
        baseURL: URL
    ) async throws -> EduPageSessionData {
        guard let student = students.first(where: { $0.id == studentID }) else {
            throw SchoolAuthenticationError.invalidStudent
        }
        var updated = session
        updated.activeStudent = student
        return updated
    }

    func restore(_ stored: EduPageSessionData, baseURL: URL) async throws -> EduPageSessionData {
        stored
    }

    func fetchMarks(baseURL: URL, session: EduPageSessionData) async throws -> MarksResponse {
        MarksResponse(subjects: [])
    }

    func fetchAbsences(baseURL: URL, session: EduPageSessionData) async throws -> AbsenceResponse {
        AbsenceResponse(percentageThreshold: nil, absences: [], absencesPerSubject: [])
    }

    func fetchUser(baseURL: URL, session: EduPageSessionData) async throws -> UserResponse {
        UserResponse(
            userUID: session.activeStudent?.id ?? "Student1",
            fullName: session.activeStudent?.fullName ?? "Test Student",
            userClass: nil,
            schoolName: session.schoolName,
            userType: "student",
            userTypeText: "Student",
            studyYear: 2026
        )
    }

    func fetchTimetable(
        baseURL: URL,
        session: EduPageSessionData,
        weekStart: Date
    ) async throws -> TimetableResponse {
        TimetableResponse()
    }

    private func sessionData(activeStudent: SchoolStudentProfile) -> EduPageSessionData {
        EduPageSessionData(
            sessionID: "ui-test-edupage-session",
            username: "parent",
            password: "secret",
            gsecHash: "ui-test-gsec",
            userID: activeStudent.id,
            schoolName: "EduPage School",
            activeStudent: activeStudent,
            linkedStudents: students,
            subjects: []
        )
    }
}
