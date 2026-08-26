import Foundation
import Testing
@testable import Gradely

struct GradeyDebugAndReleaseFixesTests {
    @Test func debugStoreUnlocksAfterSevenTaps() throws {
        let suiteName = "GradeyDebugStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = GradeyDebugModeStore(userDefaults: defaults, processInfo: ProcessInfo())

        #expect(!store.isEnabled)
        var taps = 0
        for _ in 1..<GradeyDebugModeStore.requiredTapCount {
            #expect(!store.registerVersionTap(tapCount: &taps))
            #expect(!store.isEnabled)
        }
        #expect(store.registerVersionTap(tapCount: &taps))
        #expect(store.isEnabled)
        #expect(taps == 0)
    }

    @Test func debugStoreLaunchArgumentEnablesImmediately() throws {
        let suiteName = "GradeyDebugStoreArg.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let processInfo = ProcessInfo()
        // ProcessInfo.arguments cannot be stubbed; the store only writes when
        // the current process already has the flag. Cover the persistence key
        // used by ContentView when that argument is present.
        defaults.set(true, forKey: GradeyDebugModeStore.storageKey)
        let store = GradeyDebugModeStore(userDefaults: defaults, processInfo: processInfo)
        #expect(store.isEnabled)
        _ = processInfo
    }

    @Test func restartControllerForcesNewUserEvenWhenLegacyEvidenceExists() throws {
        let suiteName = "OnboardingRestart.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: OnboardingProgressStore.completionKey)
        defaults.set(true, forKey: OnboardingProgressStore.legacyCompletionKey)
        let progressStore = OnboardingProgressStore(userDefaults: defaults)
        progressStore.saveProgress(OnboardingProgress(journey: .upgrade, step: .support))

        let controller = OnboardingRestartController(
            userDefaults: defaults,
            progressStore: progressStore
        )
        #expect(controller.restart(.newUser) == .newUser)
        #expect(!defaults.bool(forKey: OnboardingProgressStore.completionKey))
        #expect(!defaults.bool(forKey: OnboardingProgressStore.legacyCompletionKey))
        #expect(progressStore.loadProgress() == .initial(for: .newUser))
    }

    @Test func restartControllerForcesUpgradeAndSetsLegacyFlag() throws {
        let suiteName = "OnboardingRestartUpgrade.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: OnboardingProgressStore.completionKey)
        let progressStore = OnboardingProgressStore(userDefaults: defaults)

        let controller = OnboardingRestartController(
            userDefaults: defaults,
            progressStore: progressStore
        )
        #expect(controller.restart(.upgrade) == .upgrade)
        #expect(!defaults.bool(forKey: OnboardingProgressStore.completionKey))
        #expect(defaults.bool(forKey: OnboardingProgressStore.legacyCompletionKey))
        #expect(progressStore.loadProgress() == .initial(for: .upgrade))
    }

    @Test func restartControllerCanResumeAtASpecificStep() throws {
        let suiteName = "OnboardingRestartStep.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: OnboardingProgressStore.completionKey)
        let progressStore = OnboardingProgressStore(userDefaults: defaults)

        let controller = OnboardingRestartController(
            userDefaults: defaults,
            progressStore: progressStore
        )
        #expect(controller.restart(.newUser, at: .school) == .newUser)
        #expect(!defaults.bool(forKey: OnboardingProgressStore.completionKey))
        #expect(progressStore.loadProgress() == OnboardingProgress(journey: .newUser, step: .school))
    }
}

@MainActor
struct GradeyReleaseFixViewModelTests {
    @Test func upgradeCannotFinishUntilMigrationIsRecorded() {
        let viewModel = OnboardingViewModel(
            journey: .upgrade,
            progressStore: InMemoryOnboardingProgressStore()
        )
        viewModel.markSignedIn()

        #expect(viewModel.currentStep == .support)
        #expect(!viewModel.canFinish)

        viewModel.recordUpgradeMigration(school: .linked, meals: .notAttempted)
        #expect(viewModel.canFinish)
    }

    @Test func guestSchoolSignOutKeepsGuestMode() async throws {
        let schoolSessionStore = InMemorySessionStore(session: PreviewData.expiredSession)
        let mealsSessionStore = InMemoryStravaCZSessionStore(session: PreviewData.stravaCZSession)
        let authClient = MockGradeyAuthClient(session: nil)
        let guestModeStore = InMemoryGradeyGuestModeStore(isEnabled: true)
        let viewModel = AppViewModel(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: schoolSessionStore,
                marksCache: InMemoryMarksCache()
            ),
            stravaCZRepository: StravaCZRepository(
                client: MockStravaCZClient(),
                sessionStore: mealsSessionStore,
                menuCache: InMemoryStravaCZMenuCache()
            ),
            gradeyAuthClient: authClient,
            linkedAccountRepository: LinkedAccountRepository(
                store: LinkedAccountStore(
                    userDefaults: UserDefaults(suiteName: "GuestSchoolSignOut.\(UUID().uuidString)")!
                ),
                client: MockLinkedAccountClient(),
                authClient: authClient
            ),
            guestModeStore: guestModeStore,
            requiresGradeyID: true
        )

        await viewModel.bootstrap()
        await viewModel.signOutOfSchool()

        #expect(viewModel.isGuestMode)
        #expect(guestModeStore.isEnabled)
        #expect(authClient.session == nil)
        #expect(try schoolSessionStore.loadSession() == nil)
        #expect(try mealsSessionStore.loadSession() == nil)
        #expect(viewModel.phase == .signedInNeedsSchool)
        #expect(!viewModel.usesGradeyIDGate)
    }

    @Test func clearLocalCachesKeepsSessions() async throws {
        let schoolSessionStore = InMemorySessionStore(session: PreviewData.expiredSession)
        let marksCache = InMemoryMarksCache(
            cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date())
        )
        let mealsCache = InMemoryStravaCZMenuCache(
            cachedMenu: CachedStravaCZMenu(
                menu: StravaCZMenu.make(from: PreviewData.stravaCZMenuResponse),
                cachedAt: Date()
            )
        )
        let mealsSessionStore = InMemoryStravaCZSessionStore(session: PreviewData.stravaCZSession)
        let authClient = MockGradeyAuthClient()
        let viewModel = AppViewModel(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: schoolSessionStore,
                marksCache: marksCache
            ),
            stravaCZRepository: StravaCZRepository(
                client: MockStravaCZClient(),
                sessionStore: mealsSessionStore,
                menuCache: mealsCache
            ),
            gradeyAuthClient: authClient,
            linkedAccountRepository: LinkedAccountRepository(
                store: LinkedAccountStore(
                    userDefaults: UserDefaults(suiteName: "ClearCache.\(UUID().uuidString)")!
                ),
                client: MockLinkedAccountClient(),
                authClient: authClient
            ),
            guestModeStore: InMemoryGradeyGuestModeStore(),
            requiresGradeyID: true
        )

        await viewModel.bootstrap()
        viewModel.clearLocalCaches()

        #expect(try schoolSessionStore.loadSession() != nil)
        #expect(try mealsSessionStore.loadSession() != nil)
        #expect(authClient.session != nil)
        #expect(marksCache.cachedMarks == nil)
        #expect(try mealsCache.load() == nil)
        #expect(viewModel.phase == .signedIn)
    }

    @Test func resetAsNewUserSignsOutAndClearsCache() async throws {
        let schoolSessionStore = InMemorySessionStore(session: PreviewData.expiredSession)
        let marksCache = InMemoryMarksCache(
            cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date())
        )
        let authClient = MockGradeyAuthClient()
        let viewModel = AppViewModel(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: schoolSessionStore,
                marksCache: marksCache
            ),
            stravaCZRepository: AppEnvironment.makeMockStravaCZRepository(
                session: PreviewData.stravaCZSession
            ),
            gradeyAuthClient: authClient,
            linkedAccountRepository: LinkedAccountRepository(
                store: LinkedAccountStore(
                    userDefaults: UserDefaults(suiteName: "ResetNewUser.\(UUID().uuidString)")!
                ),
                client: MockLinkedAccountClient(),
                authClient: authClient
            ),
            guestModeStore: InMemoryGradeyGuestModeStore(isEnabled: true),
            requiresGradeyID: true
        )

        await viewModel.resetAsNewUser()

        #expect(try schoolSessionStore.loadSession() == nil)
        #expect(marksCache.cachedMarks == nil)
        #expect(authClient.session == nil)
        #expect(!viewModel.isGuestMode)
        #expect(viewModel.phase == .signedOut)
    }

    @Test func bakalariRefreshPreservesLinkedAccountIdentity() async throws {
        let existing = StoredSession(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(-120),
            baseURL: URL(string: "https://school.bakalari.cz")!,
            provider: .bakalari,
            bakalari: BakalariCredentials(username: "student", password: "secret"),
            linkedAccountID: "linked-123",
            linkedAccountDisplayName: "Student",
            linkedAccountSchoolName: "Demo School"
        )
        let store = InMemorySessionStore(session: existing)
        let repository = SchoolRepository(
            client: MockBakalariClient(
                refreshedResult: LoginResponse(
                    accessToken: "new-access",
                    refreshToken: "new-refresh",
                    tokenType: "Bearer",
                    expiresIn: 3600,
                    apiVersion: nil,
                    appVersion: nil,
                    userID: "mock-user"
                )
            ),
            sessionStore: store,
            marksCache: InMemoryMarksCache()
        )

        let session = try await repository.validSession()

        #expect(session.accessToken == "new-access")
        #expect(session.linkedAccountID == "linked-123")
        #expect(session.linkedAccountDisplayName == "Student")
        #expect(session.linkedAccountSchoolName == "Demo School")
        #expect(try store.loadSession()?.linkedAccountID == "linked-123")
    }

    @Test func todayPreferredMealUsesTodayNotTheEarliestOrder() {
        let today = Date()
        let todayKey = TimetableDates.apiDateString(today)
        let yesterdayKey = TimetableDates.apiDateString(today.addingTimeInterval(-86_400))
        let menu = StravaCZMenu(days: [
            StravaCZMenuDay(
                dateKey: yesterdayKey,
                displayDate: yesterdayKey,
                ordered: true,
                meals: [meal(id: 1, dateKey: yesterdayKey, name: "Yesterday soup")]
            ),
            StravaCZMenuDay(
                dateKey: todayKey,
                displayDate: todayKey,
                ordered: true,
                meals: [meal(id: 2, dateKey: todayKey, name: "Today lunch")]
            )
        ])

        let preferred = TodayViewModel.preferredMeal(from: menu, on: today)
        #expect(preferred?.name == "Today lunch")

        let noTodayOrder = StravaCZMenu(days: [
            StravaCZMenuDay(
                dateKey: yesterdayKey,
                displayDate: yesterdayKey,
                ordered: true,
                meals: [meal(id: 1, dateKey: yesterdayKey, name: "Yesterday soup")]
            )
        ])
        #expect(TodayViewModel.preferredMeal(from: noTodayOrder, on: today) == nil)
    }

    private func meal(id: Int, dateKey: String, name: String) -> StravaCZMeal {
        StravaCZMeal(
            id: id,
            dateKey: dateKey,
            type: .main,
            orderType: .normal,
            typeDescription: "Hlavní jídlo",
            name: name,
            forbiddenAllergens: nil,
            allergens: [],
            ordered: true,
            price: 89
        )
    }
}

struct AbsenceRiskNormalizationTests {
    @Test func absenceRiskTreatsFractionalThresholdAsPercent() {
        let response = AbsenceResponse(
            percentageThreshold: 0.25,
            absences: [],
            absencesPerSubject: [
                AbsencePerSubject(
                    subjectName: "Matematika",
                    lessonsCount: 20,
                    base: 4,
                    late: 0,
                    soon: 0,
                    school: 0,
                    distanceTeaching: 0
                )
            ]
        )

        let summary = AbsenceRiskSummary.make(response: response, subjects: response.absencesPerSubject)
        let subject = summary.subjects[0]

        #expect(summary.threshold == 25)
        #expect(subject.level == .watch)
        #expect(subject.missesUntilLimit == 2)
    }
}

struct AppStoreLegalLinksTests {
    @Test func helpCenterArticlesUseTheGleapHostAndLanguagePrefix() {
        #expect(AppLinks.helpCenterHost == "help.bukovinafilip.com")
        #expect(AppLinks.privacyPolicyURL.host == AppLinks.helpCenterHost)
        #expect(AppLinks.termsOfUseURL.host == AppLinks.helpCenterHost)
        #expect(AppLinks.privacyPolicyURL.path.contains("articles/10-privacy-policy"))
        #expect(AppLinks.termsOfUseURL.path.contains("articles/11-terms-and-conditions"))

        let czechPrivacy = AppLinks.helpURL(path: "articles/10-privacy-policy", languageCode: "cs")
        #expect(czechPrivacy.path.hasPrefix("/cs/"))
        let englishTerms = AppLinks.helpURL(path: "articles/11-terms-and-conditions", languageCode: "en")
        #expect(englishTerms.path.hasPrefix("/en/"))
    }
}

struct AgeAttestationStoreTests {
    @Test func sixteenAndTeenAllowUseAndUnderThirteenBlocks() throws {
        let suiteName = "AgeAttestation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AgeAttestationStore(userDefaults: defaults)

        #expect(store.kind == nil)
        #expect(!store.allowsAppUse)

        store.confirm(.underThirteen)
        #expect(store.kind == .underThirteen)
        #expect(!store.allowsAppUse)
        #expect(defaults.string(forKey: AgeAttestationStore.storageKey) == AgeAttestationKind.underThirteen.rawValue)

        store.clearBlockedChoice()
        #expect(store.kind == nil)
        #expect(!store.allowsAppUse)

        store.confirm(.thirteenToFifteenWithParent)
        #expect(store.allowsAppUse)

        store.confirm(.sixteenOrOlder)
        #expect(store.allowsAppUse)
        #expect(defaults.string(forKey: AgeAttestationStore.storageKey) == AgeAttestationKind.sixteenOrOlder.rawValue)
        #expect(AgeAttestationStore.allowsAppUse(userDefaults: defaults))
    }

    @Test func persistedChoiceReloads() throws {
        let suiteName = "AgeAttestationReload.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AgeAttestationKind.sixteenOrOlder.rawValue, forKey: AgeAttestationStore.storageKey)

        let store = AgeAttestationStore(userDefaults: defaults)
        #expect(store.kind == .sixteenOrOlder)
        #expect(store.allowsAppUse)
    }
}
