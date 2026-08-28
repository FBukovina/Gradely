import Foundation
import Testing
@testable import Gradely

@MainActor
struct OnboardingViewModelTests {
    @Test func viewModelInitializationDoesNotWriteProgressDuringViewConstruction() {
        let progress = OnboardingProgress(journey: .upgrade, step: .support)
        let store = InMemoryOnboardingProgressStore(savedProgress: progress)

        let viewModel = OnboardingViewModel(journey: .upgrade, progressStore: store)

        #expect(viewModel.currentStep == .support)
        #expect(store.savedProgress == progress)
        #expect(store.saveCount == 0)
    }

    @Test func progressStorePersistsJourneyAndStepTogether() throws {
        let suiteName = "OnboardingViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingProgressStore(userDefaults: defaults)
        let progress = OnboardingProgress(journey: .upgrade, step: .support)

        store.saveProgress(progress)

        #expect(store.loadProgress() == progress)
        let data = try #require(defaults.data(forKey: OnboardingProgressStore.storageKey))
        #expect(try JSONDecoder().decode(OnboardingProgress.self, from: data) == progress)

        store.clear()
        #expect(store.loadProgress() == nil)
    }

    @Test func progressStoreRepairsStepOnlyPrereleaseStateAsNewUserJourney() throws {
        let suiteName = "OnboardingViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("notifications", forKey: OnboardingProgressStore.storageKey)

        let progress = OnboardingProgressStore(userDefaults: defaults).loadProgress()

        #expect(progress == OnboardingProgress(journey: .newUser, step: .notifications))
    }

    @Test func routeResolverUsesV2ThenProgressThenLegacyEvidence() {
        let completedStore = InMemoryOnboardingProgressStore(
            journey: .upgrade,
            step: .support
        )
        #expect(OnboardingRouteResolver.resolve(
            hasCompletedV2: true,
            hasCompletedV1: true,
            hasLegacySchoolSession: true,
            progressStore: completedStore
        ) == nil)
        #expect(completedStore.savedProgress == nil)

        let resumedStore = InMemoryOnboardingProgressStore(
            journey: .newUser,
            step: .school
        )
        #expect(OnboardingRouteResolver.resolve(
            hasCompletedV2: false,
            hasCompletedV1: true,
            hasLegacySchoolSession: true,
            progressStore: resumedStore
        ) == .newUser)
        #expect(resumedStore.savedProgress?.step == .school)

        let legacyFlagStore = InMemoryOnboardingProgressStore()
        #expect(OnboardingRouteResolver.resolve(
            hasCompletedV2: false,
            hasCompletedV1: true,
            hasLegacySchoolSession: false,
            progressStore: legacyFlagStore
        ) == .upgrade)
        #expect(legacyFlagStore.savedProgress == .initial(for: .upgrade))

        let legacySessionStore = InMemoryOnboardingProgressStore()
        #expect(OnboardingRouteResolver.resolve(
            hasCompletedV2: false,
            hasCompletedV1: false,
            hasLegacySchoolSession: true,
            progressStore: legacySessionStore
        ) == .upgrade)

        let freshStore = InMemoryOnboardingProgressStore()
        #expect(OnboardingRouteResolver.resolve(
            hasCompletedV2: false,
            hasCompletedV1: false,
            hasLegacySchoolSession: false,
            progressStore: freshStore
        ) == .newUser)
        #expect(freshStore.savedProgress == .initial(for: .newUser))
    }

    @Test func routingFromLegacyCompletionPreservesTheV1Marker() throws {
        let suiteName = "OnboardingViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: OnboardingProgressStore.legacyCompletionKey)
        let store = OnboardingProgressStore(userDefaults: defaults)

        let journey = OnboardingRouteResolver.resolve(
            hasCompletedV2: defaults.bool(forKey: OnboardingProgressStore.completionKey),
            hasCompletedV1: defaults.bool(forKey: OnboardingProgressStore.legacyCompletionKey),
            hasLegacySchoolSession: false,
            progressStore: store
        )

        #expect(journey == .upgrade)
        #expect(defaults.bool(forKey: OnboardingProgressStore.legacyCompletionKey))
        #expect(store.loadProgress() == .initial(for: .upgrade))
    }

    @Test func newUserJourneyAllowsGuestThenRequiresSchool() {
        let store = InMemoryOnboardingProgressStore()
        let viewModel = OnboardingViewModel(journey: .newUser, progressStore: store)

        #expect(viewModel.currentStep == .welcome)
        #expect(viewModel.visibleSteps == [.account, .school, .notifications, .ready])

        viewModel.advanceFromWelcome()
        viewModel.chooseGuest()

        #expect(viewModel.accountMode == .guest)
        #expect(viewModel.currentStep == .school)
        #expect(!viewModel.visibleSteps.contains(.notifications))
        #expect(!viewModel.canFinish)

        viewModel.markSchoolConnected(cloudLink: .notApplicable)
        #expect(viewModel.currentStep == .ready)
        #expect(viewModel.canFinish)
        #expect(viewModel.finish())
        #expect(store.savedProgress == nil)
    }

    @Test func newUserHappyPathConnectsSchoolOffersNotificationsAndFinishes() {
        let store = InMemoryOnboardingProgressStore()
        let viewModel = OnboardingViewModel(journey: .newUser, progressStore: store)

        viewModel.advanceFromWelcome()
        viewModel.markSignedIn()
        #expect(viewModel.currentStep == .school)

        viewModel.markSchoolConnected(cloudLink: .linked)
        #expect(viewModel.currentStep == .notifications)

        viewModel.markNotification(.enabled)
        #expect(viewModel.currentStep == .ready)
        #expect(viewModel.canFinish)
        #expect(viewModel.finish())
        #expect(store.savedProgress == nil)
    }

    @Test func newUserCloudLinkFailurePreservesLocalSchoolAndAllowsEntry() {
        let viewModel = OnboardingViewModel(
            journey: .newUser,
            progressStore: InMemoryOnboardingProgressStore()
        )

        viewModel.advanceFromWelcome()
        viewModel.markSignedIn()
        viewModel.markSchoolConnected(cloudLink: .failed(message: "Offline"))

        #expect(viewModel.currentStep == .ready)
        #expect(viewModel.hasSchoolConnection)
        #expect(viewModel.notificationStatus == .unavailable)
        #expect(!viewModel.visibleSteps.contains(.notifications))
        #expect(viewModel.warnings == [
            OnboardingWarning(kind: .schoolCloudLink, message: "Offline")
        ])
        #expect(viewModel.canFinish)
    }

    @Test func successfulSchoolRetryReopensNotificationChoiceThenReturnsToReady() {
        let viewModel = OnboardingViewModel(
            journey: .newUser,
            progressStore: InMemoryOnboardingProgressStore()
        )
        viewModel.advanceFromWelcome()
        viewModel.markSignedIn()
        viewModel.markSchoolConnected(cloudLink: .failed())

        viewModel.recordSchoolCloudLinkRetry(.linked)
        #expect(viewModel.openNotificationsAfterSchoolLinkRetry())
        #expect(viewModel.currentStep == .notifications)

        viewModel.skipNotifications()
        #expect(viewModel.currentStep == .ready)
        #expect(viewModel.notificationStatus == .notNow)
    }

    @Test func notificationSyncFailureIsRetryableAndNonBlocking() {
        let viewModel = OnboardingViewModel(
            journey: .newUser,
            progressStore: InMemoryOnboardingProgressStore()
        )
        viewModel.advanceFromWelcome()
        viewModel.markSignedIn()
        viewModel.markSchoolConnected(cloudLink: .linked)
        viewModel.markNotification(.enabled)

        viewModel.recordNotificationSyncFailure("Could not sync")

        #expect(viewModel.canFinish)
        #expect(viewModel.warnings.contains(
            OnboardingWarning(kind: .notificationPreferences, message: "Could not sync")
        ))

        viewModel.clearNotificationSyncFailure()
        #expect(viewModel.warnings.isEmpty)
    }

    @Test func onboardingUsesTheExistingPrivateNotificationDefaults() {
        let preferences = NotificationPreferences.default

        #expect(preferences.newMarksEnabled)
        #expect(preferences.lockScreenDetail == .markAndSubject)
        #expect(!preferences.quietHoursEnabled)
    }

    @Test func landingOffersGetStartedAndLogInForBothJourneys() {
        let newUser = OnboardingViewModel(
            journey: .newUser,
            progressStore: InMemoryOnboardingProgressStore()
        )
        #expect(newUser.currentStep == .welcome)
        newUser.chooseLogIn()
        #expect(newUser.currentStep == .account)
        #expect(newUser.accountIntent == .logIn)

        let upgrade = OnboardingViewModel(
            journey: .upgrade,
            progressStore: InMemoryOnboardingProgressStore()
        )
        #expect(upgrade.currentStep == .welcome)
        upgrade.chooseGetStarted()
        #expect(upgrade.currentStep == .account)
        #expect(upgrade.accountIntent == .getStarted)
    }

    @Test func upgradeJourneyAllowsGuestThenShowsSupport() {
        let store = InMemoryOnboardingProgressStore()
        let viewModel = OnboardingViewModel(journey: .upgrade, progressStore: store)

        #expect(viewModel.currentStep == .welcome)
        viewModel.chooseGetStarted()
        viewModel.chooseGuest()

        #expect(viewModel.accountMode == .guest)
        #expect(viewModel.currentStep == .support)
        #expect(viewModel.canFinish)
        #expect(viewModel.finish())
        #expect(store.savedProgress == nil)
    }

    @Test func restoredGradeyIDSkipsUpgradeAccountAndSurfacesMigrationFailures() {
        let store = InMemoryOnboardingProgressStore(
            journey: .upgrade,
            step: .account
        )
        let viewModel = OnboardingViewModel(journey: .upgrade, progressStore: store)

        viewModel.reconcile(with: OnboardingSnapshot(
            accountMode: .gradeyID,
            hasSchoolConnection: true,
            isSchoolCloudLinked: false,
            hasMealsConnection: true,
            isMealsCloudLinked: false
        ))

        #expect(viewModel.currentStep == .support)
        #expect(!viewModel.canFinish)

        viewModel.recordUpgradeMigration(
            school: .failed(message: "School failed"),
            meals: .failed(message: "Meals failed")
        )

        #expect(viewModel.warnings == [
            OnboardingWarning(kind: .schoolCloudLink, message: "School failed"),
            OnboardingWarning(kind: .mealsCloudLink, message: "Meals failed")
        ])

        viewModel.recordSchoolCloudLinkRetry(.linked)
        viewModel.recordMealsCloudLinkRetry(.linked)
        #expect(viewModel.warnings.isEmpty)
        #expect(viewModel.canFinish)
    }

    @Test func relaunchRepairsNewUserProgressWithoutChangingJourney() {
        let store = InMemoryOnboardingProgressStore(
            journey: .newUser,
            step: .ready
        )
        let viewModel = OnboardingViewModel(journey: .newUser, progressStore: store)

        viewModel.reconcile(with: OnboardingSnapshot(accountMode: .gradeyID))

        #expect(viewModel.currentStep == .school)
        #expect(store.savedProgress == OnboardingProgress(journey: .newUser, step: .school))
        #expect(!viewModel.canFinish)
    }

    @Test func restoredSignedInSessionCompletesNewUserOnboarding() {
        let store = InMemoryOnboardingProgressStore(journey: .newUser, step: .account)
        let viewModel = OnboardingViewModel(journey: .newUser, progressStore: store)

        viewModel.reconcile(with: OnboardingSnapshot(
            accountMode: .gradeyID,
            hasSchoolConnection: true,
            isSchoolCloudLinked: true
        ))

        #expect(viewModel.completeRestoredSession())
        #expect(viewModel.isFinished)
        #expect(store.savedProgress == nil)
    }

    @Test func restoredSessionDoesNotCompleteUpgradeOrMissingSchool() {
        let upgrade = OnboardingViewModel(
            journey: .upgrade,
            progressStore: InMemoryOnboardingProgressStore()
        )
        upgrade.markSignedIn()
        #expect(!upgrade.completeRestoredSession())

        let missingSchool = OnboardingViewModel(
            journey: .newUser,
            progressStore: InMemoryOnboardingProgressStore(journey: .newUser, step: .account)
        )
        missingSchool.markSignedIn()
        #expect(!missingSchool.completeRestoredSession())
    }
}
