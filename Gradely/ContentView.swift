import SwiftUI

struct ContentView: View {
    private static let supportPromptVersion = "1.4"

    private let repository: BakalariRepository
    private let schoolDirectoryProvider: any SchoolDirectoryProviding
    private let supportTipProvider: any SupportTipProviding
    private let skipsOnboarding: Bool
    private let suppressesVersionSupportPrompt: Bool
    private let forcesVersionSupportPrompt: Bool
    @AppStorage("onboarding.completed.v1") private var hasCompletedOnboarding = false
    @AppStorage("supportPrompt.presentedVersion") private var presentedSupportPromptVersion = ""
    @State private var appViewModel: AppViewModel
    @State private var isVersionSupportPromptPresented = false
    @State private var isSupportTipSheetPresented = false
    @State private var didForcePresentSupportPrompt = false

    init(
        environment: AppEnvironment = .current(),
        skipsOnboarding: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI"),
        suppressesVersionSupportPrompt: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI")
            && !ProcessInfo.processInfo.arguments.contains("-uiTestingShowSupportPrompt"),
        forcesVersionSupportPrompt: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingShowSupportPrompt")
    ) {
        repository = environment.repository
        schoolDirectoryProvider = environment.schoolDirectoryProvider
        supportTipProvider = environment.supportTipProvider
        self.skipsOnboarding = skipsOnboarding
        self.suppressesVersionSupportPrompt = suppressesVersionSupportPrompt
        self.forcesVersionSupportPrompt = forcesVersionSupportPrompt
        _appViewModel = State(initialValue: AppViewModel(repository: environment.repository))
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
                    LoginView(repository: repository, schoolDirectoryProvider: schoolDirectoryProvider) {
                        appViewModel.markSignedIn()
                    }
                case .signedIn:
                    TabView {
                        SubjectsView(repository: repository, supportTipProvider: supportTipProvider) {
                            appViewModel.signOut()
                        }
                        .tabItem {
                            Label("subjects.title", systemImage: "checkmark.seal.fill")
                        }

                        AbsenceView(repository: repository, supportTipProvider: supportTipProvider) {
                            appViewModel.signOut()
                        }
                        .tabItem {
                            Label("absence.title", systemImage: "calendar.badge.exclamationmark")
                        }

                        TimetableView(repository: repository, supportTipProvider: supportTipProvider) {
                            appViewModel.signOut()
                        }
                        .tabItem {
                            Label("rozvrh.title", systemImage: "calendar")
                        }
                    }
                    .tint(Brand.primary)
                }
            }
        }
        .task {
            await appViewModel.bootstrap()
            presentVersionSupportPromptIfNeeded()
        }
        .onChange(of: appViewModel.phase) {
            presentVersionSupportPromptIfNeeded()
        }
        .onChange(of: hasCompletedOnboarding) {
            presentVersionSupportPromptIfNeeded()
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
            repository: BakalariRepository(
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
            repository: BakalariRepository(
                client: MockBakalariClient(),
                sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
                marksCache: InMemoryMarksCache(cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date()))
            ),
            schoolDirectoryProvider: MockSchoolDirectoryProvider(refreshResult: PreviewData.schoolDirectorySchools)
        )
    )
}
