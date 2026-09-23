import SwiftUI
import CoreSpotlight

private enum AppTab: Hashable {
    case today
    case subjects
    case absence
    case timetable
    case stravaCZ
}

struct ContentView: View {
    private let repository: SchoolRepository
    private let siriService: GradeyIntentService
    private let schoolSnapshotStore: SchoolSnapshotStore
    private let stravaCZRepository: StravaCZRepository
    private let schoolDirectoryProvider: any SchoolDirectoryProviding
    private let supportTipProvider: any SupportTipProviding
    private let watchSyncService: (any WatchSyncing)?
    private let gradeyAIClient: any GradeyAIClient
    private let gradeyAIContextBuilder: any GradeyAIContextBuilding
    private let gradeyAuthClient: any GradeyAuthClient
    private let linkedAccountRepository: LinkedAccountRepository
    private let historyRepository: GradeyHistoryRepository
    private let devicePushTokenClient: any DevicePushTokenClient
    private let notificationSettingsStore: MarkNotificationSettingsStore
    private let notificationAuthorizer: any NotificationAuthorizing
    private let onboardingProgressStore: OnboardingProgressStore
    private let skipsOnboarding: Bool
    @AppStorage(OnboardingProgressStore.completionKey) private var hasCompletedOnboardingV2 = false
    @AppStorage("settings.showMealsTab") private var showMealsTab = true
    @Bindable private var languageStore = AppLanguageStore.shared
    @State private var ageAttestationStore = AgeAttestationStore.shared
    @State private var privacyPolicyStore = PrivacyPolicyConsentStore.shared
    @State private var appViewModel: AppViewModel
    @State private var plannerStore: PlannerStore
    @State private var gradeyAIViewModel: GradeyAIViewModel
    @State private var onboardingJourney: OnboardingJourney?
    @State private var plannerTarget: PlannerNavigationTarget?
    @State private var siriSubjectID: String?
    @State private var siriSubjectRequestID: UUID?
    @State private var schoolRouteRequestID = UUID()
    @State private var siriLessonTarget: GradeySiriDestination?
    @State private var siriRouteError: String?
    @State private var notificationRouter = SchoolNotificationRouter.shared
    @AppStorage(PlannerNotificationScheduler.enabledKey) private var plannerRemindersEnabled = false
    private let plannerNotificationScheduler = PlannerNotificationScheduler()
    @State private var isGradeyAIPresented = false
    @State private var waitingForAIDismissal = false
    @State private var waitingForPolicyDismissal = false
    @State private var selectedTab: AppTab = .today
    @State private var schoolAccountRevision = UUID()
    @State private var isOnboardingForced = false
    @Environment(\.scenePhase) private var scenePhase

    init(
        environment: AppEnvironment? = nil,
        siriService: GradeyIntentService? = nil,
        skipsOnboarding: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI")
            && !ProcessInfo.processInfo.arguments.contains("-uiTestingShowOnboarding")
            && !ProcessInfo.processInfo.arguments.contains("-uiTestingShowUpgradeOnboarding"),
        notificationAuthorizer: (any NotificationAuthorizing)? = nil
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard
        let progressStore = OnboardingProgressStore(userDefaults: defaults)
        if arguments.contains("-uiTestingResetOnboarding") {
            defaults.removeObject(forKey: OnboardingProgressStore.legacyCompletionKey)
            defaults.removeObject(forKey: OnboardingProgressStore.completionKey)
            progressStore.clear()
        }
        if arguments.contains("-uiTestingShowUpgradeOnboarding") {
            defaults.set(true, forKey: OnboardingProgressStore.legacyCompletionKey)
            defaults.removeObject(forKey: OnboardingProgressStore.completionKey)
            progressStore.clear()
        }
        if arguments.contains("-uiTestingRestoreMealsTab") {
            defaults.set(true, forKey: "settings.showMealsTab")
        }
        if arguments.contains(GradeyDebugModeStore.launchArgument) {
            defaults.set(true, forKey: GradeyDebugModeStore.storageKey)
        }

        let environment = environment ?? AppEnvironment.current()
        repository = environment.repository
        self.siriService = siriService ?? GradeyIntentService(environment: environment)
        schoolSnapshotStore = environment.schoolSnapshotStore
        _plannerStore = State(initialValue: environment.makePlannerStore())
        stravaCZRepository = environment.stravaCZRepository
        schoolDirectoryProvider = environment.schoolDirectoryProvider
        supportTipProvider = environment.supportTipProvider
        watchSyncService = environment.watchSyncService
        gradeyAIClient = environment.gradeyAIClient
        gradeyAIContextBuilder = environment.gradeyAIContextBuilder
        gradeyAuthClient = environment.gradeyAuthClient
        linkedAccountRepository = environment.linkedAccountRepository
        historyRepository = environment.historyRepository
        devicePushTokenClient = environment.devicePushTokenClient
        notificationSettingsStore = environment.notificationSettingsStore
        onboardingProgressStore = progressStore
        if let notificationAuthorizer {
            self.notificationAuthorizer = notificationAuthorizer
        } else if arguments.contains("-uiTestingMockAPI") {
            let isDenied = arguments.contains("-uiTestingNotificationsDenied")
            let isAlreadyAuthorized = arguments.contains("-uiTestingNotificationsAuthorized")
            self.notificationAuthorizer = MockNotificationAuthorizer(
                status: isAlreadyAuthorized ? .authorized : .notDetermined,
                requestResult: isDenied ? .denied : .authorized
            )
        } else {
            self.notificationAuthorizer = PushRegistrationService.shared
        }
        self.skipsOnboarding = skipsOnboarding
        let hasLegacySchoolSession = (try? environment.repository.bootstrapSession()) != nil
        let resolvedJourney = skipsOnboarding
            ? nil
            : OnboardingRouteResolver.resolve(
                hasCompletedV2: defaults.bool(forKey: OnboardingProgressStore.completionKey),
                hasCompletedV1: defaults.bool(forKey: OnboardingProgressStore.legacyCompletionKey),
                hasLegacySchoolSession: hasLegacySchoolSession,
                progressStore: progressStore
            )
        _onboardingJourney = State(initialValue: resolvedJourney)
        _appViewModel = State(initialValue: AppViewModel(
            repository: environment.repository,
            stravaCZRepository: environment.stravaCZRepository,
            gradeyAuthClient: environment.gradeyAuthClient,
            linkedAccountRepository: environment.linkedAccountRepository,
            accountSettingsClient: environment.devicePushTokenClient,
            notificationSettingsStore: environment.notificationSettingsStore,
            guestModeStore: environment.guestModeStore,
            requiresGradeyID: environment.requiresGradeyID
        ))
        _gradeyAIViewModel = State(initialValue: GradeyAIViewModel(
            client: environment.gradeyAIClient,
            contextBuilder: environment.gradeyAIContextBuilder
        ))
    }

    var body: some View {
        Group {
            if !ageAttestationStore.allowsAppUse {
                AgeAttestationView(store: ageAttestationStore)
            } else if shouldShowOnboarding, let onboardingJourney {
                OnboardingView(
                    journey: onboardingJourney,
                    appViewModel: appViewModel,
                    repository: repository,
                    stravaCZRepository: stravaCZRepository,
                    schoolDirectoryProvider: schoolDirectoryProvider,
                    gradeyAuthClient: gradeyAuthClient,
                    linkedAccountRepository: linkedAccountRepository,
                    devicePushTokenClient: devicePushTokenClient,
                    notificationSettingsStore: notificationSettingsStore,
                    notificationAuthorizer: notificationAuthorizer,
                    supportTipProvider: supportTipProvider,
                    progressStore: onboardingProgressStore
                ) {
                    onboardingProgressStore.clear()
                    hasCompletedOnboardingV2 = true
                    // A brand-new install was shown the policy link during
                    // onboarding, so do not immediately re-prompt it. Upgrading
                    // users are the ones the change actually concerns, so they
                    // still get the summary after their migration finishes.
                    if onboardingJourney == .newUser {
                        privacyPolicyStore.accept()
                    }
                    isOnboardingForced = false
                    self.onboardingJourney = nil
                }
            } else {
                switch appViewModel.phase {
                case .checking:
                    SplashView()
                case .signedOut:
                    signedOutView
                case .signedInNeedsSchool:
                    needsSchoolView
                case .signedIn:
                    TabView(selection: $selectedTab) {
                        Tab("Today", image: "TabToday", value: AppTab.today) {
                            TodayView(
                                repository: repository,
                                stravaCZRepository: stravaCZRepository,
                                linkedAccountRepository: linkedAccountRepository,
                                historyRepository: historyRepository,
                                schoolDirectoryProvider: schoolDirectoryProvider,
                                accountSettingsClient: devicePushTokenClient,
                                gradeyAuthClient: gradeyAuthClient,
                                snapshotStore: schoolSnapshotStore,
                                accountHub: AnyView(accountHub()),
                                onOpenGradeyAI: presentGradeyAI,
                                onOpenAbsence: {
                                    selectedTab = .absence
                                },
                                onOpenTimetable: {
                                    selectedTab = .timetable
                                },
                                onOpenMarks: {
                                    selectedTab = .subjects
                                }
                            )
                        }

                        Tab("subjects.title", image: "TabSubjects", value: AppTab.subjects) {
                            SubjectsView(
                                repository: repository,
                                historyRepository: historyRepository,
                                snapshotStore: schoolSnapshotStore,
                                accountHub: AnyView(accountHub()),
                                onOpenGradeyAI: presentGradeyAI,
                                siriSubjectID: siriSubjectID,
                                siriRequestID: siriSubjectRequestID
                            )
                        }

                        Tab("absence.title", image: "TabAbsence", value: AppTab.absence) {
                            AbsenceView(
                                repository: repository,
                                accountHub: AnyView(accountHub()),
                                onOpenGradeyAI: presentGradeyAI
                            )
                        }

                        Tab("rozvrh.title", image: "TabTimetable", value: AppTab.timetable) {
                            TimetableView(
                                repository: repository,
                                plannerStore: plannerStore,
                                accountHub: AnyView(accountHub()),
                                onOpenGradeyAI: presentGradeyAI,
                                siriTarget: siriLessonTarget
                            )
                        }

                        if showMealsTab {
                            Tab("stravacz.title", image: "TabMeals", value: AppTab.stravaCZ) {
                                StravaCZView(
                                    repository: stravaCZRepository,
                                    linkedAccountRepository: linkedAccountRepository,
                                    accountHub: AnyView(accountHub()),
                                    onOpenGradeyAI: presentGradeyAI
                                )
                            }
                        }
                    }
                    .id(schoolAccountRevision)
                    .tint(Brand.primary)
                    .gradelySidebarAdaptable()
                }
            }
        }
        .task {
            await plannerStore.activate()
            watchSyncService?.start()
            #if !os(macOS)
            watchSyncService?.configureAIRelay(
                client: gradeyAIClient,
                contextBuilder: gradeyAIContextBuilder,
                supportProvider: supportTipProvider
            )
            await publishWatchSupportTier()
            #endif
            PushRegistrationService.shared.configure(
                client: devicePushTokenClient,
                authClient: gradeyAuthClient
            )
            await appViewModel.bootstrap()
            await consumeNotificationRoute()
            await reconcilePlannerReminders()
            resumeOnboardingIfSessionIsIncomplete()
            await PushRegistrationService.shared.refreshRegistrationIfAuthorized()
            await preloadGradeyAIIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    schoolSnapshotStore.activateCurrentScope()
                    await plannerStore.activate()
                    await schoolSnapshotStore.refresh()
                    await reconcilePlannerReminders()
                }
            }
            #if !os(macOS)
            if phase == .active {
                Task { await publishWatchSupportTier() }
            }
            #endif
        }
        .onChange(of: appViewModel.phase) {
            resumeOnboardingIfSessionIsIncomplete()
            if appViewModel.phase == .signedIn {
                selectedTab = .today
                Task {
                    await consumeNotificationRoute()
                    await reconcilePlannerReminders()
                    await preloadGradeyAIIfNeeded()
                }
            } else {
                schoolSnapshotStore.invalidateSession()
                Task { await plannerNotificationScheduler.cancelAll() }
                isGradeyAIPresented = false
                plannerTarget = nil
                siriSubjectID = nil
                siriLessonTarget = nil
                gradeyAIViewModel.reset()
            }
        }
        .onChange(of: schoolSnapshotStore.scope) {
            siriSubjectID = nil
            siriLessonTarget = nil
        }
        .onChange(of: plannerStore.items) { Task { await reconcilePlannerReminders() } }
        .onChange(of: plannerRemindersEnabled) { Task { await reconcilePlannerReminders() } }
        .onChange(of: notificationSettingsStore.preferences) { Task { await reconcilePlannerReminders() } }
        .onChange(of: notificationRouter.pendingURL) { Task { await consumeNotificationRoute() } }
        .onChange(of: shouldShowOnboarding) { Task { await consumeNotificationRoute() } }
        .onChange(of: shouldShowPrivacyPolicyUpdate) { Task { await consumeNotificationRoute() } }
        .onChange(of: ageAttestationStore.allowsAppUse) { Task { await consumeNotificationRoute() } }
        .onChange(of: showMealsTab) { _, isVisible in
            if !isVisible, selectedTab == .stravaCZ {
                selectedTab = .today
            }
        }
        .onOpenURL { url in
            Task { await handleOpenURL(url) }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let value = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let identifier = GradeySiriID(value) else { return }
            Task { await handleOpenURL(identifier.url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gradelySchoolAccountDidChange)) { _ in
            schoolSnapshotStore.activateCurrentScope()
            isGradeyAIPresented = false
            plannerTarget = nil
            gradeyAIViewModel.reset()
            selectedTab = .today
            schoolAccountRevision = UUID()
            siriSubjectID = nil
            siriLessonTarget = nil
            Task { await reconcilePlannerReminders() }
            Task { await preloadGradeyAIIfNeeded() }
        }
        .sheet(isPresented: $isGradeyAIPresented, onDismiss: {
            gradeyAIViewModel.stop()
            waitingForAIDismissal = false
            Task { await consumeNotificationRoute() }
        }) {
            GradeyAIView(
                viewModel: gradeyAIViewModel,
                supportTipProvider: supportTipProvider,
                isSignedIn: appViewModel.gradeyAccount != nil,
                isGuestMode: appViewModel.isGuestMode,
                authClient: gradeyAuthClient,
                onGuestSignedIn: {
                    await appViewModel.markGradeySignedIn()
                }
            )
        }
        .sheet(item: $plannerTarget) { target in
            NavigationStack {
                PlannerView(store: plannerStore, resolver: PlannerLessonResolver(repository: repository),
                            focusedDay: target.day, initialItemID: target.itemID)
            }
        }
        .privacyPolicyUpdate(isPresented: shouldShowPrivacyPolicyUpdate, onDismiss: {
            waitingForPolicyDismissal = false
            Task { await consumeNotificationRoute() }
        }) {
            waitingForPolicyDismissal = true
            privacyPolicyStore.accept()
        }
        .environment(\.requestGradeyAIAction) { action, subjectID, eventID in
            Task {
                let expectedGeneration = repository.sessionGeneration
                isGradeyAIPresented = true
                await gradeyAIViewModel.selectAction(action, subjectID: subjectID, eventID: eventID)
                guard repository.sessionGeneration == expectedGeneration else { return }
            }
        }
        .alert(AppL10n.string("error.title"), isPresented: Binding(get: { siriRouteError != nil }, set: { if !$0 { siriRouteError = nil } })) {
            Button("action.done") { siriRouteError = nil }
        } message: { Text(siriRouteError ?? "") }
        .environment(\.gradeySiriService, siriService)
        .environment(\.locale, languageStore.locale)
    }

    /// Never stacks on the age gate or onboarding — both are root branches
    /// rather than overlays, so this waits until the app proper is on screen.
    private var shouldShowPrivacyPolicyUpdate: Bool {
        ageAttestationStore.allowsAppUse
            && !shouldShowOnboarding
            && privacyPolicyStore.needsAcknowledgement
    }

    private var shouldShowOnboarding: Bool {
        (!skipsOnboarding || isOnboardingForced)
            && !hasCompletedOnboardingV2
            && onboardingJourney != nil
    }

    @ViewBuilder
    private var signedOutView: some View {
        if appViewModel.usesGradeyIDGate {
            SplashView()
        } else {
            LoginView(repository: repository, schoolDirectoryProvider: schoolDirectoryProvider) {
                appViewModel.markSignedIn()
            }
        }
    }

    @ViewBuilder
    private var needsSchoolView: some View {
        LoginView(
            repository: repository,
            schoolDirectoryProvider: schoolDirectoryProvider,
            onBackFromSchool: appViewModel.usesGradeyIDGate
                ? {
                    Task {
                        await appViewModel.signOut()
                        resumeOnboardingIfSessionIsIncomplete()
                    }
                }
                : nil
        ) {
            Task { await finishSchoolReconnect() }
        }
    }

    private func accountHub() -> some View {
        GradeyAccountHubView(
            account: appViewModel.gradeyAccount,
            isGuestMode: appViewModel.isGuestMode,
            repository: repository,
            stravaCZRepository: stravaCZRepository,
            schoolDirectoryProvider: schoolDirectoryProvider,
            linkedAccountRepository: linkedAccountRepository,
            notificationClient: devicePushTokenClient,
            authClient: gradeyAuthClient,
            preferencesStore: notificationSettingsStore,
            supportTipProvider: supportTipProvider,
            notificationAuthorizer: notificationAuthorizer,
            onSchoolLinked: {
                appViewModel.markSignedIn()
            },
            onSignedOut: {
                Task {
                    if appViewModel.isGuestMode {
                        await appViewModel.signOutOfSchool()
                    } else {
                        await appViewModel.signOut()
                        resumeOnboardingIfSessionIsIncomplete()
                    }
                }
            },
            onLeaveGuestMode: {
                appViewModel.leaveGuestMode()
            },
            onAccountUpdated: { account in
                appViewModel.updateGradeyAccount(account)
            },
            onRestartOnboarding: { journey in
                restartOnboarding(journey)
            },
            onDebugSignOut: {
                Task {
                    await appViewModel.signOut()
                    gradeyAIViewModel.reset()
                }
            },
            onDebugClearCache: {
                appViewModel.clearLocalCaches()
                gradeyAIViewModel.reset()
                schoolAccountRevision = UUID()
            Task { await reconcilePlannerReminders() }
            },
            onDebugResetAsNewUser: {
                Task {
                    await appViewModel.resetAsNewUser()
                    gradeyAIViewModel.reset()
                    schoolAccountRevision = UUID()
            Task { await reconcilePlannerReminders() }
                    restartOnboarding(.newUser)
                }
            }
        )
    }

    private func handleOpenURL(_ url: URL) async {
        guard SchoolNotificationRouting.isSupported(url) else { return }
        let requestID = UUID()
        schoolRouteRequestID = requestID
        notificationRouter.pendingURL = url
        if isGradeyAIPresented {
            waitingForAIDismissal = true
            isGradeyAIPresented = false
            return // Resume after the sheet's dismissal animation completes.
        }
        guard canHandleSchoolRoutes else { return }
        _ = notificationRouter.takePendingURL(ifReady: true)

        if let identifier = GradeySiriID.from(url: url) {
            do {
                let destination = try await siriService.resolveDestination(identifier.value)
                try siriService.validateDestination(destination)
                guard canHandleSchoolRoutes, schoolRouteRequestID == requestID else { return }
                if let subjectID = destination.subjectID {
                    siriSubjectID = subjectID
                    siriSubjectRequestID = destination.requestID
                    selectedTab = .subjects
                } else if destination.lesson != nil {
                    siriLessonTarget = destination
                    selectedTab = .timetable
                } else if let itemID = destination.plannerItemID {
                    selectedTab = .today
                    plannerTarget = PlannerNavigationTarget(url: URL(string: "gradey://planner/item/\(itemID.uuidString)")!)
                }
            } catch { if schoolRouteRequestID == requestID { siriRouteError = error.localizedDescription } }
        } else if let target = PlannerNavigationTarget(url: url) {
            selectedTab = .today
            plannerTarget = target
        } else if url.host == "marks"
            || url.host == "subjects"
            || url.path == "/marks"
            || url.path == "/subjects" {
            selectedTab = .subjects
        } else if url.host == "timetable" || url.path == "/timetable" {
            selectedTab = .timetable
        }
    }

    private func consumeNotificationRoute() async {
        guard let url = notificationRouter.pendingURL else { return }
        await handleOpenURL(url)
    }

    private var canHandleSchoolRoutes: Bool {
        appViewModel.phase == .signedIn && ageAttestationStore.allowsAppUse
            && !shouldShowOnboarding && !shouldShowPrivacyPolicyUpdate
            && !isGradeyAIPresented && !waitingForAIDismissal && !waitingForPolicyDismissal
    }

    private func reconcilePlannerReminders() async {
        guard appViewModel.phase == .signedIn else { await plannerNotificationScheduler.cancelAll(); return }
        schoolSnapshotStore.activateCurrentScope()
        await plannerNotificationScheduler.reconcile(items: plannerStore.items, scope: schoolSnapshotStore.scope,
                                                      preferences: notificationSettingsStore.preferences)
    }

    private func presentGradeyAI() {
        isGradeyAIPresented = true
    }

    private func preloadGradeyAIIfNeeded() async {
        guard appViewModel.phase == .signedIn, !appViewModel.isGuestMode else { return }
        async let bootstrap: Void = gradeyAIViewModel.bootstrap()
        async let entitlement = supportTipProvider.currentEntitlement()
        _ = await bootstrap
        let tier = await entitlement
        gradeyAIViewModel.applySupportTier(tier.tier, catalogLoaded: false)
    }

    #if !os(macOS)
    private func publishWatchSupportTier() async {
        let entitlement = await supportTipProvider.currentEntitlement()
        watchSyncService?.update(supportTier: WatchPayloadBuilder.supportTier(from: entitlement))
    }
    #endif

    private func finishSchoolReconnect() async {
        if appViewModel.gradeyAccount != nil, let session = try? repository.bootstrapSession() {
            let user = await repository.loadUser()
            if let account = try? await linkedAccountRepository.linkCurrentSchoolAccount(
                session: session,
                user: user
            ) {
                try? repository.associateCurrentSession(with: account)
            }
        }
        appViewModel.markSignedIn()
    }

    private func resumeOnboardingIfSessionIsIncomplete() {
        guard appViewModel.usesGradeyIDGate, appViewModel.phase == .signedOut else { return }
        if shouldShowOnboarding {
            return
        }

        restartOnboarding(.newUser, at: .account)
    }

    private func restartOnboarding(_ journey: OnboardingJourney, at step: OnboardingStep? = nil) {
        let controller = OnboardingRestartController(progressStore: onboardingProgressStore)
        hasCompletedOnboardingV2 = false
        isOnboardingForced = true
        onboardingJourney = controller.restart(journey, at: step)
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: Spacing.xl) {
                Image("GradeyLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)

                ProgressView()
                    .controlSize(.large)
                    .tint(Brand.primary)
                    .accessibilityIdentifier("bootstrapProgress")
            }
            .padding(.horizontal, Spacing.xxl)
        }
    }
}

#Preview("Signed out") {
    ContentView(
        environment: AppEnvironment(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: InMemorySessionStore(),
                marksCache: InMemoryMarksCache()
            ),
            schoolDirectoryProvider: MockSchoolDirectoryProvider(refreshResult: PreviewData.schoolDirectorySchools)
        )
    )
}

#Preview("Signed in") {
    ContentView(
        environment: AppEnvironment(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
                marksCache: InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date()))
            ),
            schoolDirectoryProvider: MockSchoolDirectoryProvider(refreshResult: PreviewData.schoolDirectorySchools)
        )
    )
}
