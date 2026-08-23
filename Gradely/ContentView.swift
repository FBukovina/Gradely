import SwiftUI

private enum AppTab: Hashable {
    case today
    case subjects
    case absence
    case timetable
    case stravaCZ
}

struct ContentView: View {
    private let repository: SchoolRepository
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
    @State private var appViewModel: AppViewModel
    @State private var gradeyAIViewModel: GradeyAIViewModel
    @State private var onboardingJourney: OnboardingJourney?
    @State private var isGradeyAIPresented = false
    @State private var selectedTab: AppTab = .today
    @State private var schoolAccountRevision = UUID()
    @State private var isOnboardingForced = false
    @Environment(\.scenePhase) private var scenePhase

    init(
        environment: AppEnvironment = .current(),
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

        repository = environment.repository
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
            if shouldShowOnboarding, let onboardingJourney {
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
                                accountHub: AnyView(accountHub()),
                                onOpenGradeyAI: presentGradeyAI,
                                onOpenAbsence: {
                                    selectedTab = .absence
                                }
                            )
                        }

                        Tab("subjects.title", image: "TabSubjects", value: AppTab.subjects) {
                            SubjectsView(
                                repository: repository,
                                historyRepository: historyRepository,
                                accountHub: AnyView(accountHub()),
                                onOpenGradeyAI: presentGradeyAI
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
                                accountHub: AnyView(accountHub()),
                                onOpenGradeyAI: presentGradeyAI
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
            resumeOnboardingIfSessionIsIncomplete()
            await PushRegistrationService.shared.refreshRegistrationIfAuthorized()
            await preloadGradeyAIIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
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
                Task { await preloadGradeyAIIfNeeded() }
            } else {
                isGradeyAIPresented = false
                gradeyAIViewModel.reset()
            }
        }
        .onChange(of: showMealsTab) { _, isVisible in
            if !isVisible, selectedTab == .stravaCZ {
                selectedTab = .today
            }
        }
        .onOpenURL { url in
            Task { await handleOpenURL(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gradelySchoolAccountDidChange)) { _ in
            isGradeyAIPresented = false
            gradeyAIViewModel.reset()
            selectedTab = .today
            schoolAccountRevision = UUID()
            Task { await preloadGradeyAIIfNeeded() }
        }
        .sheet(isPresented: $isGradeyAIPresented, onDismiss: {
            gradeyAIViewModel.stop()
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
        .environment(\.locale, languageStore.locale)
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
            },
            onDebugResetAsNewUser: {
                Task {
                    await appViewModel.resetAsNewUser()
                    gradeyAIViewModel.reset()
                    schoolAccountRevision = UUID()
                    restartOnboarding(.newUser)
                }
            }
        )
    }

    private func handleOpenURL(_ url: URL) async {
        guard url.scheme == "gradey" || url.scheme == "gradely" else { return }

        if url.host == "marks"
            || url.host == "subjects"
            || url.path == "/marks"
            || url.path == "/subjects" {
            selectedTab = .subjects
        } else if url.host == "timetable" || url.path == "/timetable" {
            selectedTab = .timetable
        }
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
