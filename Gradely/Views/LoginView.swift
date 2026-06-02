import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    let onSignedIn: () -> Void

    init(repository: BakalariRepository, onSignedIn: @escaping () -> Void) {
        _viewModel = State(initialValue: LoginViewModel(repository: repository))
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero
                    form
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xxl)
                .padding(.bottom, Spacing.xxl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .alert(String(localized: "error.title"), isPresented: errorBinding) {
            Button(String(localized: "action.ok"), role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Brand.onAccent)
                .frame(width: 64, height: 64)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .shadow(color: Brand.primary.opacity(0.45), radius: 18, x: 0, y: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("app.name")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text("login.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var form: some View {
        Card {
            VStack(spacing: Spacing.lg) {
                TextField(String(localized: "login.schoolURL"), text: $viewModel.schoolURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .brandField()
                    .accessibilityIdentifier("schoolURLField")

                TextField(String(localized: "login.username"), text: $viewModel.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .brandField()
                    .accessibilityIdentifier("usernameField")

                passwordField

                Button {
                    Task {
                        if await viewModel.login() {
                            onSignedIn()
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Brand.onAccent)
                        }
                        Text(viewModel.isLoading ? String(localized: "login.loading") : String(localized: "login.button"))
                        if !viewModel.isLoading {
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.bold))
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isLoading)
                .padding(.top, Spacing.xs)
                .accessibilityIdentifier("loginButton")
            }
        }
    }

    private var passwordField: some View {
        HStack(spacing: Spacing.sm) {
            Group {
                if viewModel.isPasswordVisible {
                    TextField(String(localized: "login.password"), text: $viewModel.password)
                } else {
                    SecureField(String(localized: "login.password"), text: $viewModel.password)
                }
            }
            .textContentType(.password)
            .submitLabel(.done)
            .accessibilityIdentifier("passwordField")

            Button {
                viewModel.isPasswordVisible.toggle()
            } label: {
                Image(systemName: viewModel.isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(viewModel.isPasswordVisible ? String(localized: "login.hidePassword") : String(localized: "login.showPassword"))
            }
            .buttonStyle(.plain)
        }
        .brandField()
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.clearError()
                }
            }
        )
    }
}

#Preview("Light") {
    LoginView(
        repository: BakalariRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache()
        )
    ) {}
}

#Preview("Dark") {
    LoginView(
        repository: BakalariRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache()
        )
    ) {}
    .preferredColorScheme(.dark)
}
