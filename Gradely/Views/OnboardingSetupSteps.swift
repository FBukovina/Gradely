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
            SettingsModalSurface(padding: Spacing.lg) {
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

// MARK: - School connection

/// Retained temporarily for source-history context only. The onboarding and
/// signed-out routes now share LoginView so the school flow has one source of truth.
struct OnboardingSchoolStep: View {
    @State private var viewModel: LoginViewModel
    @Binding private var showsCredentials: Bool
    @FocusState private var isSchoolSearchFocused: Bool
    @FocusState private var focusedCredentialField: CredentialField?
    private let onSignedIn: () -> Void

    private enum CredentialField {
        case username
        case password
    }

    init(
        repository: SchoolRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        showsCredentials: Binding<Bool>,
        onSignedIn: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: LoginViewModel(
            repository: repository,
            schoolDirectoryProvider: schoolDirectoryProvider
        ))
        _showsCredentials = showsCredentials
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        Group {
            if showsCredentials {
                credentialsScreen
                    .id("schoolCredentials")
            } else {
                schoolSelectionScreen
                    .id("schoolSelection")
            }
        }
        .alert(AppL10n.string("error.title"), isPresented: errorBinding) {
            Button(AppL10n.string("action.ok"), role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $viewModel.isTwoFactorPresented) {
            twoFactorSheet
        }
        .sheet(isPresented: $viewModel.isStudentSelectionPresented) {
            studentSelectionSheet
        }
        .task {
            await viewModel.loadSchoolDirectoryIfNeeded()
        }
        .onChange(of: isSchoolSearchFocused) { _, isFocused in
            if isFocused {
                viewModel.isSchoolSearchActive = true
            }
        }
        .onChange(of: viewModel.provider) { _, provider in
            showsCredentials = false
            guard provider == .bakalari else { return }
            Task { await viewModel.loadSchoolDirectoryIfNeeded() }
        }
        .accessibilityIdentifier("onboardingStep-school")
    }

    private var schoolSelectionScreen: some View {
        OnboardingStepScaffold(
            icon: "building.columns.fill",
            title: "onboarding.school.choose.title",
            message: "onboarding.school.choose.body",
            titleSize: 36,
            contentSpacing: Spacing.lg,
            verticalPadding: Spacing.lg
        ) {
            OnboardingSchoolStageIndicator(currentStage: 1)

            SettingsModalSurface(padding: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if SchoolProvider.showsSignInPicker {
                        providerPicker
                    }

                    if viewModel.provider == .bakalari {
                        schoolSearchPicker
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("onboarding.school.manual.label")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField(
                            AppL10n.string(viewModel.provider == .bakalari ? "login.schoolURL" : "edupage.schoolURL"),
                            text: $viewModel.schoolURL
                        )
                        .textContentType(.URL)
                        .gradelyKeyboardType(.url)
                        .gradelyTextInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .onSubmit(advanceToCredentials)
                        .brandField()
                        .accessibilityIdentifier("schoolURLField")
                    }

                    if viewModel.provider == .bakalari {
                        schoolURLManual
                    } else {
                        eduPageURLHint
                    }
                }
            }

            if ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI"),
               viewModel.provider == .bakalari {
                Button {
                    viewModel.fillDemoAccount()
                    advanceToCredentials()
                } label: {
                    GradelyLabel("login.demoAccount", systemImage: "person.badge.key.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.primary)
                .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .accessibilityIdentifier("demoAccountButton")
            }

            Button(action: advanceToCredentials) {
                HStack(spacing: Spacing.sm) {
                    Text("onboarding.school.continue")
                    GradelyIcon(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAdvanceToCredentials)
            .accessibilityIdentifier("schoolContinueButton")
        }
        .accessibilityIdentifier("onboardingSchoolSelection")
    }

    private var credentialsScreen: some View {
        OnboardingStepScaffold(
            icon: "lock.shield.fill",
            title: "onboarding.school.credentials.title",
            message: "onboarding.school.credentials.body",
            titleSize: 36,
            contentSpacing: Spacing.lg,
            verticalPadding: Spacing.lg
        ) {
            OnboardingSchoolStageIndicator(currentStage: 2)

            selectedSchoolSummary

            SettingsModalSurface(padding: Spacing.lg) {
                VStack(spacing: Spacing.md) {
                    TextField(AppL10n.string("login.username"), text: $viewModel.username)
                        .textContentType(.username)
                        .gradelyTextInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedCredentialField, equals: .username)
                        .onSubmit { focusedCredentialField = .password }
                        .brandField()
                        .accessibilityIdentifier("usernameField")

                    passwordField
                        .focused($focusedCredentialField, equals: .password)

                }
            }

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
                        Text("login.loading")
                    } else {
                        Text("onboarding.school.connect")
                        GradelyIcon(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("loginButton")
        }
        .accessibilityIdentifier("onboardingSchoolCredentials")
    }

    private var selectedSchoolSummary: some View {
        SettingsModalSurface(padding: Spacing.md) {
            HStack(spacing: Spacing.md) {
                SettingsModalSystemIcon(systemName: "building.columns.fill")
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(selectedSchoolName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text(viewModel.provider.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.sm)

                Button("onboarding.school.change") {
                    showsCredentials = false
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Brand.primary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("changeSchoolButton")
            }
        }
        .accessibilityIdentifier("selectedSchoolSummary")
    }

    private var canAdvanceToCredentials: Bool {
        !viewModel.schoolURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedSchoolName: String {
        if let selectedSchoolID = viewModel.selectedSchoolID,
           let school = viewModel.directorySchools.first(where: { $0.id == selectedSchoolID }) {
            return school.trimmedName
        }

        let searchName = viewModel.schoolSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchName.isEmpty {
            return searchName
        }

        return viewModel.schoolURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func advanceToCredentials() {
        guard canAdvanceToCredentials else { return }
        isSchoolSearchFocused = false
        focusedCredentialField = nil
        showsCredentials = true
    }

    private var providerPicker: some View {
        Picker(
            AppL10n.string("login.provider"),
            selection: Binding(
                get: { viewModel.provider },
                set: { viewModel.changeProvider($0) }
            )
        ) {
            ForEach(SchoolProvider.offeredForNewSignIn) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("schoolProviderPicker")
    }

    private var schoolSearchPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                GradelyIcon(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField(
                    AppL10n.string("schoolDirectory.search"),
                    text: Binding(
                        get: { viewModel.schoolSearchText },
                        set: { viewModel.updateSchoolSearch($0) }
                    )
                )
                .gradelyTextInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($isSchoolSearchFocused)
                .accessibilityIdentifier("schoolSearchField")

                if viewModel.isSchoolDirectoryLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Brand.primary)
                        .accessibilityIdentifier("schoolDirectoryLoading")
                }
            }
            .brandField()

            if let message = viewModel.schoolLookupErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("schoolDirectoryError")
            }

            let results = viewModel.schoolSearchResults
            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, school in
                        OnboardingSchoolResultRow(school: school) {
                            viewModel.selectSchool(school)
                            advanceToCredentials()
                        }
                        if index < results.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            } else if viewModel.isSchoolSearchActive,
                      !viewModel.schoolSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !viewModel.isSchoolDirectoryLoading,
                      viewModel.schoolLookupErrorMessage == nil,
                      !viewModel.directorySchools.isEmpty {
                Text("schoolDirectory.noResults")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("schoolDirectoryNoResults")
            }
        }
    }

    private var schoolURLManual: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                OnboardingManualStep(number: 1, text: AppL10n.string("schoolURL.manual.step1"))
                OnboardingManualStep(number: 2, text: AppL10n.string("schoolURL.manual.step2"))
                OnboardingManualStep(number: 3, text: AppL10n.string("schoolURL.manual.step3"))
                OnboardingManualStep(number: 4, text: AppL10n.string("schoolURL.manual.step4"))

                Text("schoolURL.manual.example")
                    .font(.caption.monospaced())
                    .foregroundStyle(Brand.primary)
                    .padding(.top, Spacing.xs)
            }
            .padding(.top, Spacing.sm)
        } label: {
            GradelyLabel("schoolURL.manual.title", systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
        }
        .tint(Brand.primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .accessibilityIdentifier("schoolURLManual")
    }

    private var eduPageURLHint: some View {
        GradelyLabel("edupage.schoolURL.hint", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var passwordField: some View {
        HStack(spacing: Spacing.sm) {
            Group {
                if viewModel.isPasswordVisible {
                    TextField(AppL10n.string("login.password"), text: $viewModel.password)
                } else {
                    SecureField(AppL10n.string("login.password"), text: $viewModel.password)
                }
            }
            .textContentType(.password)
            .submitLabel(.done)
            .accessibilityIdentifier("passwordField")

            Button {
                viewModel.isPasswordVisible.toggle()
            } label: {
                GradelyIcon(systemName: viewModel.isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        viewModel.isPasswordVisible
                            ? AppL10n.string("login.hidePassword")
                            : AppL10n.string("login.showPassword")
                    )
            }
            .buttonStyle(.plain)
        }
        .brandField()
    }

    private var twoFactorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(AppL10n.string("edupage.twoFactor.code"), text: $viewModel.twoFactorCode)
                        .gradelyKeyboardType(.numberPad)
                        .accessibilityIdentifier("eduPageTwoFactorCode")

                    Button(AppL10n.string("edupage.twoFactor.submit")) {
                        Task {
                            if await viewModel.completeTwoFactor() {
                                onSignedIn()
                            }
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("eduPageTwoFactorSubmit")
                } header: {
                    Text("edupage.twoFactor.codeSection")
                }

                Section {
                    Button {
                        Task {
                            if await viewModel.checkDeviceApproval() {
                                onSignedIn()
                            }
                        }
                    } label: {
                        if viewModel.isCheckingDeviceApproval {
                            ProgressView()
                        } else {
                            Text("edupage.twoFactor.checkApproval")
                        }
                    }
                    .disabled(viewModel.isCheckingDeviceApproval)
                    .accessibilityIdentifier("eduPageTwoFactorCheck")

                    Button("edupage.twoFactor.resend") {
                        Task { await viewModel.resendDeviceApproval() }
                    }
                } header: {
                    Text("edupage.twoFactor.deviceSection")
                }
            }
            .navigationTitle("edupage.twoFactor.title")
        }
        .interactiveDismissDisabled(viewModel.isLoading)
    }

    private var studentSelectionSheet: some View {
        NavigationStack {
            List(viewModel.availableStudents) { student in
                Button {
                    Task {
                        if await viewModel.selectStudent(student) {
                            onSignedIn()
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(student.fullName)
                            .foregroundStyle(.primary)
                        if let className = student.className {
                            Text(className)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(viewModel.isLoading)
                .accessibilityIdentifier("eduPageStudent-\(student.id)")
            }
            .navigationTitle("edupage.children.title")
        }
        .interactiveDismissDisabled(viewModel.isLoading)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }
}

// MARK: - Meals connection

/// Dedicated onboarding form for the optional canteen connection.
struct OnboardingMealsConnectionStep: View {
    private let repository: StravaCZRepository
    private let onConnected: (StravaCZStoredSession) async -> Void

    @State private var canteenNumber = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    init(
        repository: StravaCZRepository,
        onConnected: @escaping (StravaCZStoredSession) async -> Void
    ) {
        self.repository = repository
        self.onConnected = onConnected
    }

    var body: some View {
        OnboardingStepScaffold(
            icon: "fork.knife",
            title: "onboarding.meals.connect.title",
            message: "onboarding.meals.connect.body"
        ) {
            SettingsModalSurface(padding: Spacing.lg) {
                VStack(spacing: Spacing.md) {
                    TextField(AppL10n.string("stravacz.canteenNumber"), text: $canteenNumber)
                        .gradelyKeyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .submitLabel(.next)
                        .brandField()
                        .accessibilityIdentifier("stravaCZCanteenField")

                    TextField(AppL10n.string("stravacz.username"), text: $username)
                        .textContentType(.username)
                        .gradelyTextInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .brandField()
                        .accessibilityIdentifier("stravaCZUsernameField")

                    HStack(spacing: Spacing.sm) {
                        Group {
                            if isPasswordVisible {
                                TextField(AppL10n.string("stravacz.password"), text: $password)
                            } else {
                                SecureField(AppL10n.string("stravacz.password"), text: $password)
                            }
                        }
                        .textContentType(.password)
                        .submitLabel(.done)
                        .accessibilityIdentifier("stravaCZPasswordField")

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            GradelyIcon(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(
                                    isPasswordVisible
                                        ? AppL10n.string("login.hidePassword")
                                        : AppL10n.string("login.showPassword")
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .brandField()
                }
            }

            Button {
                Task { await connect() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Brand.onAccent)
                        Text("stravacz.connect.loading")
                    } else {
                        Text("stravacz.connect.button")
                        GradelyIcon(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isConnecting)
            .accessibilityIdentifier("stravaCZConnectButton")
        }
        .alert(AppL10n.string("error.title"), isPresented: errorBinding) {
            Button(AppL10n.string("action.ok"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityIdentifier("onboardingStep-mealsForm")
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
            if let localizedError = error as? LocalizedError,
               let message = localizedError.errorDescription {
                errorMessage = message
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
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
            SettingsModalBackground()

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

private struct OnboardingSchoolStageIndicator: View {
    let currentStage: Int

    var body: some View {
        HStack(spacing: Spacing.sm) {
            stage(
                number: 1,
                title: "onboarding.school.stage.school",
                isCurrent: currentStage == 1,
                isComplete: currentStage > 1
            )

            GradelyIcon(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            stage(
                number: 2,
                title: "onboarding.school.stage.credentials",
                isCurrent: currentStage == 2,
                isComplete: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schoolStageIndicator")
    }

    private func stage(
        number: Int,
        title: LocalizedStringKey,
        isCurrent: Bool,
        isComplete: Bool
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            GradelyIcon(systemName: isComplete ? "checkmark.circle.fill" : "\(number).circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isCurrent || isComplete ? Brand.primary : Color.secondary)

            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 40)
        .background(
            isCurrent ? Brand.primary.opacity(0.13) : Color.gradelyTertiaryFill,
            in: Capsule()
        )
        .accessibilityIdentifier("schoolStage-\(number)")
    }
}

private struct OnboardingManualStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text("\(number).")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Brand.primary)
                .frame(width: 22, alignment: .trailing)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingSchoolResultRow: View {
    let school: SchoolDirectorySchool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                SettingsModalSystemIcon(systemName: "building.columns.fill", size: 15)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(school.trimmedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("\(school.trimmedTown) · \(school.trimmedSchoolURL)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: Spacing.sm)

                GradelyIcon(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("schoolResult-\(school.id)")
    }
}
