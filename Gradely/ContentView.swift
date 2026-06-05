import SwiftUI

struct ContentView: View {
    private let repository: BakalariRepository
    private let schoolDirectoryProvider: any SchoolDirectoryProviding
    private let skipsOnboarding: Bool
    @AppStorage("onboarding.completed.v1") private var hasCompletedOnboarding = false
    @State private var appViewModel: AppViewModel

    init(
        environment: AppEnvironment = .current(),
        skipsOnboarding: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI")
    ) {
        repository = environment.repository
        schoolDirectoryProvider = environment.schoolDirectoryProvider
        self.skipsOnboarding = skipsOnboarding
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
                        SubjectsView(repository: repository) {
                            appViewModel.signOut()
                        }
                        .tabItem {
                            Label("subjects.title", systemImage: "checkmark.seal.fill")
                        }

                        TimetableView(repository: repository) {
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
        }
    }

    private var shouldShowOnboarding: Bool {
        !skipsOnboarding && !hasCompletedOnboarding
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
