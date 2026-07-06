import SwiftUI

/// Standalone Strava.cz login form, shared by the Meals tab (signed-out phase)
/// and the account hub's "Connect Strava.cz" push. Carries no NavigationStack;
/// the parent supplies one.
struct StravaCZConnectView: View {
    private let repository: StravaCZRepository
    private let onConnected: (StravaCZStoredSession) async -> Void

    @State private var canteenNumber: String
    @State private var username: String
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    init(
        repository: StravaCZRepository,
        initialCanteenNumber: String = "",
        initialUsername: String = "",
        onConnected: @escaping (StravaCZStoredSession) async -> Void
    ) {
        self.repository = repository
        self.onConnected = onConnected
        _canteenNumber = State(initialValue: initialCanteenNumber)
        _username = State(initialValue: initialUsername)
    }

    var body: some View {
        ZStack {
            Color.gradelyGroupedBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Brand.onAccent)
                            .frame(width: 64, height: 64)
                            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .shadow(color: Brand.primary.opacity(0.35), radius: 14, x: 0, y: 8)
                            .accessibilityHidden(true)

                        Text("stravacz.connect.title")
                            .font(.title.bold())
                            .foregroundStyle(.primary)

                        Text("stravacz.connect.message")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Card {
                        VStack(spacing: Spacing.lg) {
                            TextField(String(localized: "stravacz.canteenNumber"), text: $canteenNumber)
                                .gradelyKeyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .submitLabel(.next)
                                .brandField()
                                .accessibilityIdentifier("stravaCZCanteenField")

                            TextField(String(localized: "stravacz.username"), text: $username)
                                .textContentType(.username)
                                .gradelyTextInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .brandField()
                                .accessibilityIdentifier("stravaCZUsernameField")

                            passwordField

                            Button {
                                Task { await connect() }
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    if isConnecting {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(Brand.onAccent)
                                    }
                                    Text(isConnecting ? String(localized: "stravacz.connect.loading") : String(localized: "stravacz.connect.button"))
                                    if !isConnecting {
                                        Image(systemName: "chevron.right")
                                            .font(.subheadline.weight(.bold))
                                    }
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isConnecting)
                            .accessibilityIdentifier("stravaCZConnectButton")
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.xxl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityIdentifier("stravaCZConnectView")
        .alert(String(localized: "error.title"), isPresented: errorBinding) {
            Button(String(localized: "action.ok"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var passwordField: some View {
        HStack(spacing: Spacing.sm) {
            Group {
                if isPasswordVisible {
                    TextField(String(localized: "stravacz.password"), text: $password)
                } else {
                    SecureField(String(localized: "stravacz.password"), text: $password)
                }
            }
            .textContentType(.password)
            .submitLabel(.done)
            .accessibilityIdentifier("stravaCZPasswordField")

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(isPasswordVisible ? String(localized: "login.hidePassword") : String(localized: "login.showPassword"))
            }
            .buttonStyle(.plain)
        }
        .brandField()
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        do {
            let session = try await repository.login(
                canteenNumber: canteenNumber,
                username: username,
                password: password
            )
            password = ""
            await onConnected(session)
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}

#Preview {
    NavigationStack {
        StravaCZConnectView(repository: AppEnvironment.makeMockStravaCZRepository()) { _ in }
    }
}
