import SwiftUI

private enum AppTab: Hashable {
    case today
    case subjects
    case absence
    case timetable
    case stravaCZ
}

struct ContentView: View {
    private static let supportPromptVersion = "1.4"

    private let repository: SchoolRepository
    private let stravaCZRepository: StravaCZRepository
    private let schoolDirectoryProvider: any SchoolDirectoryProviding
    private let supportTipProvider: any SupportTipProviding
    private let watchSyncService: (any WatchSyncing)?
    private let gradeyAuthClient: any GradeyAuthClient
    private let linkedAccountRepository: LinkedAccountRepository
    private let historyRepository: GradeyHistoryRepository
    private let devicePushTokenClient: any DevicePushTokenClient
    private let notificationSettingsStore: MarkNotificationSettingsStore
    private let skipsOnboarding: Bool
    private let suppressesVersionSupportPrompt: Bool
    private let forcesVersionSupportPrompt: Bool
    @AppStorage("onboarding.completed.v1") private var hasCompletedOnboarding = false
    @AppStorage("supportPrompt.presentedVersion") private var presentedSupportPromptVersion = ""
    @State private var appViewModel: AppViewModel
    @State private var isVersionSupportPromptPresented = false
    @State private var isSupportTipSheetPresented = false
    @State private var didForcePresentSupportPrompt = false
    @State private var selectedTab: AppTab = .today
    @State private var schoolAccountRevision = UUID()

    init(
        environment: AppEnvironment = .current(),
        skipsOnboarding: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI"),
        suppressesVersionSupportPrompt: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI")
            && !ProcessInfo.processInfo.arguments.contains("-uiTestingShowSupportPrompt"),
        forcesVersionSupportPrompt: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingShowSupportPrompt")
    ) {
        repository = environment.repository
        stravaCZRepository = environment.stravaCZRepository
        schoolDirectoryProvider = environment.schoolDirectoryProvider
        supportTipProvider = environment.supportTipProvider
        watchSyncService = environment.watchSyncService
        gradeyAuthClient = environment.gradeyAuthClient
        linkedAccountRepository = environment.linkedAccountRepository
        historyRepository = environment.historyRepository
        devicePushTokenClient = environment.devicePushTokenClient
        notificationSettingsStore = environment.notificationSettingsStore
        self.skipsOnboarding = skipsOnboarding
        self.suppressesVersionSupportPrompt = suppressesVersionSupportPrompt
        self.forcesVersionSupportPrompt = forcesVersionSupportPrompt
        _appViewModel = State(initialValue: AppViewModel(
            repository: environment.repository,
            stravaCZRepository: environment.stravaCZRepository,
            gradeyAuthClient: environment.gradeyAuthClient,
            linkedAccountRepository: environment.linkedAccountRepository,
            requiresGradeyID: environment.requiresGradeyID
        ))
    }

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
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
                        Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                            TodayView(
                                repository: repository,
                                stravaCZRepository: stravaCZRepository,
                                linkedAccountRepository: linkedAccountRepository,
                                historyRepository: historyRepository,
                                supportTipProvider: supportTipProvider,
                                accountHub: AnyView(accountHub),
                                onOpenMarks: {
                                    selectedTab = .subjects
                                },
                                onOpenAbsence: {
                                    selectedTab = .absence
                                }
                            ) {
                                Task { await appViewModel.signOut() }
                            }
                        }

                        Tab("subjects.title", systemImage: "checkmark.seal.fill", value: AppTab.subjects) {
                            SubjectsView(
                                repository: repository,
                                historyRepository: historyRepository,
                                supportTipProvider: supportTipProvider,
                                accountHub: AnyView(accountHub)
                            ) {
                                Task { await appViewModel.signOut() }
                            }
                        }

                        Tab("absence.title", systemImage: "calendar.badge.exclamationmark", value: AppTab.absence) {
                            AbsenceView(
                                repository: repository,
                                supportTipProvider: supportTipProvider,
                                accountHub: AnyView(accountHub)
                            ) {
                                Task { await appViewModel.signOut() }
                            }
                        }

                        Tab("rozvrh.title", systemImage: "calendar", value: AppTab.timetable) {
                            TimetableView(
                                repository: repository,
                                supportTipProvider: supportTipProvider,
                                accountHub: AnyView(accountHub)
                            ) {
                                Task { await appViewModel.signOut() }
                            }
                        }

                        Tab("stravacz.title", systemImage: "fork.knife", value: AppTab.stravaCZ) {
                            StravaCZView(
                                repository: stravaCZRepository,
                                linkedAccountRepository: linkedAccountRepository
                            )
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
            PushRegistrationService.shared.configure(
                client: devicePushTokenClient,
                authClient: gradeyAuthClient,
                preferencesStore: notificationSettingsStore
            )
            await appViewModel.bootstrap()
            presentVersionSupportPromptIfNeeded()
        }
        .onChange(of: appViewModel.phase) {
            presentVersionSupportPromptIfNeeded()
        }
        .onChange(of: hasCompletedOnboarding) {
            presentVersionSupportPromptIfNeeded()
        }
        .onOpenURL { url in
            Task { await handleOpenURL(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gradelySchoolAccountDidChange)) { _ in
            selectedTab = .today
            schoolAccountRevision = UUID()
        }
        .alert(String(localized: "support.updatePrompt.title"), isPresented: $isVersionSupportPromptPresented) {
            Button(String(localized: "support.updatePrompt.later"), role: .cancel) {}
            Button(String(localized: "support.updatePrompt.support")) {
                isSupportTipSheetPresented = true
            }
        } message: {
            Text("support.updatePrompt.message")
        }
        .sheet(isPresented: $isSupportTipSheetPresented) {
            SupportTipView(
                viewModel: SupportTipViewModel(
                    supportTipProvider: supportTipProvider
                )
            )
        }
    }

    private var shouldShowOnboarding: Bool {
        !skipsOnboarding && !hasCompletedOnboarding
    }

    @ViewBuilder
    private var signedOutView: some View {
        if appViewModel.usesGradeyIDGate {
            GradeyIDLoginView(
                authClient: gradeyAuthClient,
                onBypassForTesting: {
                    Task { await appViewModel.bypassGradeyIDForTesting() }
                }
            ) {
                Task { await appViewModel.markGradeySignedIn() }
            }
        } else {
            LoginView(repository: repository, schoolDirectoryProvider: schoolDirectoryProvider) {
                appViewModel.markSignedIn()
            }
        }
    }

    @ViewBuilder
    private var needsSchoolView: some View {
        if appViewModel.usesGradeyIDGate {
            accountHub
        } else {
            LoginView(repository: repository, schoolDirectoryProvider: schoolDirectoryProvider) {
                appViewModel.markSignedIn()
            }
        }
    }

    private var accountHub: some View {
        GradeyAccountHubView(
            account: appViewModel.gradeyAccount,
            repository: repository,
            stravaCZRepository: stravaCZRepository,
            schoolDirectoryProvider: schoolDirectoryProvider,
            linkedAccountRepository: linkedAccountRepository,
            notificationClient: devicePushTokenClient,
            authClient: gradeyAuthClient,
            preferencesStore: notificationSettingsStore,
            onSchoolLinked: {
                appViewModel.markSignedIn()
            },
            onSignedOut: {
                Task { await appViewModel.signOut() }
            }
        )
    }

    private func handleOpenURL(_ url: URL) async {
        guard url.scheme == "gradey" || url.scheme == "gradely" else { return }

        if url.host == "timetable" || url.path == "/timetable" {
            selectedTab = .timetable
        }
    }

    private func presentVersionSupportPromptIfNeeded() {
        guard appViewModel.phase == .signedIn,
              !shouldShowOnboarding,
              !isVersionSupportPromptPresented,
              !isSupportTipSheetPresented
        else {
            return
        }

        if forcesVersionSupportPrompt {
            guard !didForcePresentSupportPrompt else {
                return
            }
            didForcePresentSupportPrompt = true
            isVersionSupportPromptPresented = true
            return
        }

        guard !suppressesVersionSupportPrompt,
              currentAppVersion == Self.supportPromptVersion,
              presentedSupportPromptVersion != Self.supportPromptVersion
        else {
            return
        }

        presentedSupportPromptVersion = Self.supportPromptVersion
        isVersionSupportPromptPresented = true
    }

    private var currentAppVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Brand.gradient
                .ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Brand.primary)
                    .frame(width: 88, height: 88)
                    .background(.white, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)

                ProgressView()
                    .controlSize(.large)
                    .tint(Brand.onAccent)
                    .accessibilityIdentifier("bootstrapProgress")
            }
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
