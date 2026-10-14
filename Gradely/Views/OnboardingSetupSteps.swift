import AuthenticationServices
import SwiftUI

// MARK: - Gradey ID

/// First-run and returning-user Gradey ID sign-in. This is the only full-screen
/// account setup surface; settings never hosts that flow.
struct OnboardingAccountStep: View {
    @State private var viewModel: GradeyIDViewModel
    private let accountIntent: OnboardingAccountIntent
    private let onContinueWithoutAccount: (() -> Void)?
    private let onSignedIn: () -> Void

    init(
        journey _: OnboardingJourney,
        accountIntent: OnboardingAccountIntent = .getStarted,
        authClient: any GradeyAuthClient,
        onContinueWithoutAccount: (() -> Void)? = nil,
        onSignedIn: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: GradeyIDViewModel(authClient: authClient))
        self.accountIntent = accountIntent
        self.onContinueWithoutAccount = onContinueWithoutAccount
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        OnboardingStepScaffold(
            icon: "person.crop.circle.badge.checkmark",
            title: accountIntent == .logIn
                ? "onboarding.account.login.title"
                : "onboarding.account.title",
            message: accountIntent == .logIn
                ? "onboarding.account.login.body"
                : "onboarding.account.body"
        ) {
            SettingsSurface(padding: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("gradey.auth.signInBody")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GradelyAppleSignInButton(
                        isLoading: viewModel.isLoading,
                        onCompletion: handleAppleResult,
                        onMockSignIn: signInForUITesting
                    )

                    if viewModel.isLoading {
                        HStack(spacing: Spacing.sm) {
                            ProgressView()
                                .controlSize(.small)
                            Text("gradey.auth.signingIn")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("gradeyIDSigningIn")
                    }
                }
            }

            if let onContinueWithoutAccount {
                Button(action: onContinueWithoutAccount) {
                    GradelyLabel("onboarding.upgrade.account.continueWithout", systemImage: "arrow.right.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.primary)
                .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .disabled(viewModel.isLoading)
                .accessibilityIdentifier("gradeyIDBypassButton")
            }
        }
        .alert("gradey.auth.title", isPresented: errorBinding) {
            Button("action.ok", role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .accessibilityIdentifier("onboardingStep-account")
    }

    private func signInForUITesting() {
        Task {
            if await viewModel.signInWithApple(identityToken: "ui-test", nonce: nil, fullName: nil) {
                onSignedIn()
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                viewModel.errorMessage = GradeyAuthError.missingIdentityToken.errorDescription
                return
            }

            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            Task {
                if await viewModel.signInWithApple(
                    identityToken: token,
                    nonce: nil,
                    fullName: fullName.isEmpty ? nil : fullName
                ) {
                    onSignedIn()
                }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }
}

// MARK: - Shared onboarding language

struct OnboardingStepScaffold<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let titleSize: CGFloat
    let contentSpacing: CGFloat
    let verticalPadding: CGFloat
    @ViewBuilder let content: Content

    init(
        icon: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        titleSize: CGFloat = 38,
        contentSpacing: CGFloat = Spacing.xl,
        verticalPadding: CGFloat = Spacing.xxl,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.titleSize = titleSize
        self.contentSpacing = contentSpacing
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        ZStack {
            SettingsBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    OnboardingStepHero(icon: icon, title: title, message: message, titleSize: titleSize)
                    content
                }
                .padding(.horizontal, 20)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

struct OnboardingStepHero: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var titleSize: CGFloat = 38

    var body: some View {
        SettingsModalFlowHero(
            icon: icon,
            title: title,
            message: message,
            titleSize: min(titleSize, 36)
        )
    }
}
