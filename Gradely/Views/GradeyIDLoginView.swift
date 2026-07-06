import AuthenticationServices
import SwiftUI

struct GradeyIDLoginView: View {
    @State private var viewModel: GradeyIDViewModel
    let onBypassForTesting: (() -> Void)?
    let onSignedIn: () -> Void

    init(
        authClient: any GradeyAuthClient,
        onBypassForTesting: (() -> Void)? = nil,
        onSignedIn: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: GradeyIDViewModel(authClient: authClient))
        self.onBypassForTesting = onBypassForTesting
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        ZStack {
            GradeyTwoPointZeroBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    hero
                    signInCard
                    privacyNote
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xxl)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
        }
        .alert("gradey.auth.title", isPresented: errorBinding) {
            Button("action.ok", role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(Brand.gradient)
                    .shadow(color: Brand.primary.opacity(0.18), radius: 18, x: 0, y: 8)
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Brand.onAccent)
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("gradey.auth.title")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("gradey.auth.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signInCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("gradey.auth.signInHeading")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("gradey.auth.signInBody")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    handleAppleResult(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .disabled(viewModel.isLoading)
                .accessibilityIdentifier("gradeyIDAppleButton")

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

                #if DEBUG
                if let onBypassForTesting {
                    Divider()
                        .padding(.vertical, Spacing.xs)

                    Button {
                        onBypassForTesting()
                    } label: {
                        Label("gradey.auth.testingBypass", systemImage: "arrow.right.circle")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .disabled(viewModel.isLoading)
                    .accessibilityIdentifier("gradeyIDBypassButton")
                }
                #endif
            }
        }
    }

    private var privacyNote: some View {
        Label("gradey.auth.privacyNote", systemImage: "lock.shield.fill")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.gradelySecondaryGroupedBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                if await viewModel.signInWithApple(identityToken: token, nonce: nil, fullName: fullName.isEmpty ? nil : fullName) {
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

struct GradeyTwoPointZeroBackground: View {
    var body: some View {
        ZStack {
            Color.gradelyGroupedBackground
            LinearGradient(
                colors: [
                    Brand.primary.opacity(0.10),
                    Color.gradelyGroupedBackground,
                    Brand.secondary.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

#Preview("Gradey ID") {
    GradeyIDLoginView(authClient: MockGradeyAuthClient(session: nil)) {}
}
