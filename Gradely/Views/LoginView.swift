import SwiftUI

struct LoginView: View {
    enum PresentationContext: Equatable {
        case standalone
        case linking
        case reconnecting

        var buttonTitle: LocalizedStringKey {
            switch self {
            case .standalone: "login.button"
            case .linking: "gradey.account.linkSchool.button"
            case .reconnecting: "settings.connected.reconnect"
            }
        }

        var showsRepositoryLink: Bool {
            self == .standalone
        }
    }

    private enum Stage: Int {
        case school = 1
        case credentials = 2
    }

    private enum CredentialField {
        case username
        case password
    }

    @State private var viewModel: LoginViewModel
    @State private var stage: Stage = .school
    @FocusState private var isSchoolSearchFocused: Bool
    @FocusState private var focusedCredentialField: CredentialField?
    private let presentationContext: PresentationContext
    private let onBackFromSchool: (() -> Void)?
    let onSignedIn: () -> Void

    init(
        repository: SchoolRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        presentationContext: PresentationContext = .standalone,
        prefill: SchoolLoginPrefill? = nil,
        onBackFromSchool: (() -> Void)? = nil,
        onSignedIn: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: LoginViewModel(
            repository: repository,
            schoolDirectoryProvider: schoolDirectoryProvider,
            prefill: prefill
        ))
        _stage = State(initialValue: prefill == nil ? .school : .credentials)
        self.presentationContext = presentationContext
        self.onBackFromSchool = onBackFromSchool
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        ZStack {
            SettingsModalBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    flowHeader
                    if !isSchoolSearchFocused || stage == .credentials {
                        stageHero
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Group {
                        switch stage {
                        case .school:
                            schoolSelectionContent
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        case .credentials:
                            credentialsContent
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                    .id(stage)

                    if presentationContext.showsRepositoryLink, stage == .school {
                        githubLink
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, Spacing.lg)
                .padding(.bottom, 124)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .animation(.snappy(duration: 0.34), value: stage)
        .animation(.easeInOut(duration: 0.2), value: isSchoolSearchFocused)
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
            stage = .school
            guard provider == .bakalari else { return }
            Task { await viewModel.loadSchoolDirectoryIfNeeded() }
        }
    }

    private var flowHeader: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                if stage == .credentials {
                    Button(action: returnToSchoolSelection) {
                        GradelyLabel("onboarding.back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.primary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(backButtonIdentifier)
                } else if let onBackFromSchool {
                    Button(action: onBackFromSchool) {
                        GradelyLabel("onboarding.back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.primary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboardingBackButton")
                } else {
                    Color.clear
                        .frame(width: 84, height: 44)
                }

                Spacer()

                Text(stage == .school ? "onboarding.school.stage.school" : "onboarding.school.stage.credentials")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(Brand.gradient)
                        .frame(width: proxy.size.width * (stage == .school ? 0.5 : 1))
                }
            }
            .frame(height: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stage == .school ? "onboarding.school.stage.school" : "onboarding.school.stage.credentials")
            .accessibilityValue("\(stage.rawValue) / 2")
        }
    }

    private var stageHero: some View {
        SettingsModalFlowHero(
            icon: stage == .school ? "building.columns.fill" : "lock.shield.fill",
            title: stage == .school ? "onboarding.school.choose.title" : "onboarding.school.credentials.title",
            message: stage == .school ? "onboarding.school.choose.body" : "onboarding.school.credentials.body"
        )
    }

    private var schoolSelectionContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            providerChooser

            SettingsModalSurface(padding: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if viewModel.provider == .bakalari {
                        schoolSearchPicker
                        if !isSchoolSearchFocused {
                            Divider()
                            manualSchoolAddress
                        }
                    } else {
                        manualSchoolAddress
                    }
                }
            }

            if ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI"),
               viewModel.provider == .bakalari,
               !isSchoolSearchFocused {
                Button {
                    viewModel.fillDemoAccount()
                    moveToCredentials()
                } label: {
                    GradelyLabel("login.demoAccount", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.primary)
                .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .accessibilityIdentifier("demoAccountButton")
            }
        }
    }

    private var providerChooser: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("login.provider")
                .font(.gradelyDisplay(size: 20, relativeTo: .title3))

            HStack(spacing: Spacing.sm) {
                ForEach(SchoolProvider.allCases) { provider in
                    Button {
                        viewModel.changeProvider(provider)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            GradelyIcon(
                                systemName: provider == .bakalari ? "building.2.fill" : "person.2.fill",
                                size: 15
                            )
                            Text(provider.displayName)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(viewModel.provider == provider ? Brand.onAccent : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(
                                    viewModel.provider == provider
                                        ? AnyShapeStyle(Brand.gradient)
                                        : AnyShapeStyle(Color.gradelyTertiaryFill)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Color.primary.opacity(viewModel.provider == provider ? 0 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("provider-\(provider.rawValue)")
                    .accessibilityAddTraits(viewModel.provider == provider ? .isSelected : [])
                }
            }
        }
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
                .submitLabel(.search)
                .focused($isSchoolSearchFocused)
                .onSubmit { isSchoolSearchFocused = false }
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
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("schoolDirectoryError")

                    Spacer(minLength: Spacing.sm)

                    Button {
                        Task { await viewModel.retrySchoolDirectory() }
                    } label: {
                        GradelyLabel("action.retry", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.primary)
                    .accessibilityIdentifier("schoolDirectoryRetryButton")
                }
                .font(.caption.weight(.semibold))
            }

            let results = viewModel.schoolSearchResults
            if !results.isEmpty {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, school in
                            SchoolResultRow(school: school) {
                                viewModel.selectSchool(school)
                                isSchoolSearchFocused = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                    moveToCredentials()
                                }
                            }
                            if index < results.count - 1 {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
                .scrollIndicators(.visible)
                .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .accessibilityIdentifier("schoolSearchResults")
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

    private var manualSchoolAddress: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(viewModel.provider == .bakalari ? "onboarding.school.manual.label" : "edupage.schoolURL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.sm) {
                GradelyIcon(systemName: "link")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField(
                    AppL10n.string(viewModel.provider == .bakalari ? "login.schoolURL" : "edupage.schoolURL"),
                    text: $viewModel.schoolURL
                )
                .textContentType(.URL)
                .gradelyKeyboardType(.url)
                .gradelyTextInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .onSubmit(moveToCredentials)
                .accessibilityIdentifier("schoolURLField")
            }
            .brandField()

            if viewModel.provider == .bakalari {
                schoolURLManual
            } else {
                GradelyLabel("edupage.schoolURL.hint", systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var schoolURLManual: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ManualStep(number: 1, text: AppL10n.string("schoolURL.manual.step1"))
                ManualStep(number: 2, text: AppL10n.string("schoolURL.manual.step2"))
                ManualStep(number: 3, text: AppL10n.string("schoolURL.manual.step3"))
                ManualStep(number: 4, text: AppL10n.string("schoolURL.manual.step4"))

                Text("schoolURL.manual.example")
                    .font(.caption.monospaced())
                    .foregroundStyle(Brand.primary)
                    .padding(.top, Spacing.xs)
            }
            .padding(.top, Spacing.sm)
        } label: {
            GradelyLabel("schoolURL.manual.title", systemImage: "questionmark.circle")
                .font(.footnote.weight(.semibold))
        }
        .tint(Brand.primary)
        .accessibilityIdentifier("schoolURLManual")
    }

    private var credentialsContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            selectedSchoolSummary

            SettingsModalSurface(padding: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
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
                }
            }
        }
    }

    private var selectedSchoolSummary: some View {
        HStack(spacing: Spacing.md) {
            SettingsModalSystemIcon(systemName: "building.columns.fill")
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(selectedSchoolName)
                    .font(.gradelyDisplay(size: 18, relativeTo: .headline))
                    .lineLimit(2)

                Text(viewModel.provider.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            Button("onboarding.school.change", action: returnToSchoolSelection)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Brand.primary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("changeSchoolButton")
        }
        .padding(20)
        .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .accessibilityIdentifier("selectedSchoolSummary")
    }

    private var actionBar: some View {
        Button {
            if stage == .school {
                moveToCredentials()
            } else {
                Task {
                    if await viewModel.login() {
                        onSignedIn()
                    }
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
                    Text(stage == .school ? "onboarding.school.continue" : presentationContext.buttonTitle)
                    GradelyIcon(
                        systemName: stage == .school ? "arrow.right" : "checkmark",
                        size: 14
                    )
                }
            }
        }
        .buttonStyle(LoginActionButtonStyle())
        .disabled(stage == .school ? !canMoveToCredentials : viewModel.isLoading)
        .accessibilityIdentifier(stage == .school ? "schoolContinueButton" : "loginButton")
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity)
    }

    private var passwordField: some View {
        HStack(spacing: Spacing.sm) {
            GradelyIcon(systemName: "key.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Group {
                if viewModel.isPasswordVisible {
                    TextField(AppL10n.string("login.password"), text: $viewModel.password)
                } else {
                    SecureField(AppL10n.string("login.password"), text: $viewModel.password)
                }
            }
            .textContentType(.password)
            .focused($focusedCredentialField, equals: .password)
            .submitLabel(.done)
            .onSubmit {
                Task {
                    if await viewModel.login() {
                        onSignedIn()
                    }
                }
            }
            .accessibilityIdentifier("passwordField")

            Button {
                viewModel.isPasswordVisible.toggle()
            } label: {
                GradelyIcon(systemName: viewModel.isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(viewModel.isPasswordVisible ? AppL10n.string("login.hidePassword") : AppL10n.string("login.showPassword"))
            }
            .buttonStyle(.plain)
        }
        .brandField()
        .contentShape(Rectangle())
        .onTapGesture {
            focusedCredentialField = .password
        }
    }

    private var githubLink: some View {
        Link(destination: AppLinks.githubRepositoryURL) {
            Label {
                Text("github.repository")
            } icon: {
                GitHubIcon(size: 16)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Brand.primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("githubRepositoryLink")
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

    private var canMoveToCredentials: Bool {
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

    private func moveToCredentials() {
        guard canMoveToCredentials else { return }
        isSchoolSearchFocused = false
        focusedCredentialField = nil
        withAnimation(.snappy(duration: 0.34)) {
            stage = .credentials
        }
    }

    private func returnToSchoolSelection() {
        focusedCredentialField = nil
        withAnimation(.snappy(duration: 0.34)) {
            stage = .school
        }
    }

    private var backButtonIdentifier: String {
        onBackFromSchool == nil ? "loginBackButton" : "onboardingBackButton"
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

private struct LoginActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(isEnabled ? Brand.onAccent : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        isEnabled
                            ? AnyShapeStyle(Brand.gradient)
                            : AnyShapeStyle(Color.gradelyTertiaryFill)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isEnabled ? Brand.primary.opacity(0.16) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(isEnabled ? 0.10 : 0.03),
                radius: 3,
                x: 0,
                y: 2
            )
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct ManualStep: View {
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

private struct SchoolResultRow: View {
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

                SettingsModalDisclosureIcon()
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                onSelect()
            }
        )
        .accessibilityIdentifier("schoolResult-\(school.id)")
    }
}

#Preview("Light") {
    LoginView(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache()
        ),
        schoolDirectoryProvider: MockSchoolDirectoryProvider(refreshResult: PreviewData.schoolDirectorySchools)
    ) {}
}

#Preview("Dark") {
    LoginView(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache()
        ),
        schoolDirectoryProvider: MockSchoolDirectoryProvider(refreshResult: PreviewData.schoolDirectorySchools)
    ) {}
    .preferredColorScheme(.dark)
}
