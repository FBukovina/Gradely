import SwiftUI

struct ContentView: View {
    private let repository: BakalariRepository
    private let skipsOnboarding: Bool
    @AppStorage("onboarding.completed.v1") private var hasCompletedOnboarding = false
    @State private var appViewModel: AppViewModel

    init(
        environment: AppEnvironment = .current(),
        skipsOnboarding: Bool = ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI")
    ) {
        repository = environment.repository
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
                    LoginView(repository: repository) {
                        appViewModel.markSignedIn()
                    }
                case .signedIn:
                    SubjectsView(repository: repository) {
                        appViewModel.signOut()
                    }
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
            )
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
            )
        )
    )
}
