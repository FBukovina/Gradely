import SwiftUI

/// Password-from-the-course-card form, shared by the Taneční screen and
/// Settings. Carries no NavigationStack; the parent supplies one.
struct VavruskaConnectView: View {
    let viewModel: VavruskaViewModel
    var usesScreenBackground = false
    /// Pushed on its own (reconnect): pop back once the course is connected.
    var dismissesOnConnect = false
    var onConnected: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if usesScreenBackground {
                AuroraBackground()
            } else {
                SettingsBackground()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    SettingsModalFlowHero(
                        title: "vavruska.connect.title",
                        message: "vavruska.connect.message"
                    )

                    SettingsSurface {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            passwordField

                            Text("vavruska.connect.hint")
                                .font(.gradely(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                Task { await connect() }
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    if isConnecting {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(Brand.onAccent)
                                    }
                                    Text(isConnecting ? AppL10n.string("vavruska.connect.loading") : AppL10n.string("vavruska.connect.button"))
                                    if !isConnecting {
                                        GradelyIcon(systemName: "chevron.right", size: 14)
                                    }
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isConnecting || password.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("vavruskaConnectButton")

                            Text("vavruska.connect.privacy")
                                .font(.gradely(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.xxl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityIdentifier("vavruskaConnectView")
        .alert(AppL10n.string("error.title"), isPresented: errorBinding) {
            Button(AppL10n.string("action.ok"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Not marked as a password field: the code is printed on a card, and
    /// iOS offering to save it in Passwords would only confuse.
    private var passwordField: some View {
        HStack(spacing: Spacing.sm) {
            Group {
                if isPasswordVisible {
                    TextField(AppL10n.string("vavruska.connect.password"), text: $password)
                } else {
                    SecureField(AppL10n.string("vavruska.connect.password"), text: $password)
                }
            }
            .autocorrectionDisabled()
            .gradelyTextInputAutocapitalization(.never)
            .submitLabel(.go)
            .onSubmit { Task { await connect() } }
            .accessibilityIdentifier("vavruskaPasswordField")

            Button {
                isPasswordVisible.toggle()
            } label: {
                GradelyIcon(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(isPasswordVisible ? AppL10n.string("login.hidePassword") : AppL10n.string("login.showPassword"))
            }
            .buttonStyle(.plain)
        }
        .brandField()
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func connect() async {
        guard !isConnecting else { return }
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        do {
            try await viewModel.connect(password: password)
            password = ""
            await onConnected()
            if dismissesOnConnect {
                dismiss()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        VavruskaConnectView(viewModel: VavruskaViewModel(repository: AppEnvironment.makeMockVavruskaRepository()))
    }
}
