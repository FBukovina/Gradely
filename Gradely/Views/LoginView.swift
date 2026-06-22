import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    @FocusState private var isSchoolSearchFocused: Bool
    let onSignedIn: () -> Void

    init(
        repository: SchoolRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        onSignedIn: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: LoginViewModel(
            repository: repository,
            schoolDirectoryProvider: schoolDirectoryProvider
        ))
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero
                    form
                    githubLink
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
            guard provider == .bakalari else { return }
            Task { await viewModel.loadSchoolDirectoryIfNeeded() }
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
                providerPicker

                if viewModel.provider == .bakalari {
                    schoolSearchPicker
                }

                TextField(
                    String(localized: viewModel.provider == .bakalari ? "login.schoolURL" : "edupage.schoolURL"),
                    text: $viewModel.schoolURL
                )
                    .textContentType(.URL)
                    .gradelyKeyboardType(.url)
                    .gradelyTextInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .brandField()
                    .accessibilityIdentifier("schoolURLField")

                if viewModel.provider == .bakalari {
                    schoolURLManual
                } else {
                    eduPageURLHint
                }

                TextField(String(localized: "login.username"), text: $viewModel.username)
                    .textContentType(.username)
                    .gradelyTextInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .brandField()
                    .accessibilityIdentifier("usernameField")

                passwordField

                if viewModel.provider == .bakalari {
                    Button {
                        viewModel.fillDemoAccount()
                    } label: {
                        Label(String(localized: "login.demoAccount"), systemImage: "person.badge.key.fill")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.primary)
                    .accessibilityIdentifier("demoAccountButton")
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

    private var providerPicker: some View {
        Picker(
            String(localized: "login.provider"),
            selection: Binding(
                get: { viewModel.provider },
                set: { viewModel.changeProvider($0) }
            )
        ) {
            ForEach(SchoolProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("schoolProviderPicker")
    }

    private var schoolSearchPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField(
                    String(localized: "schoolDirectory.search"),
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
                        SchoolResultRow(school: school) {
                            viewModel.selectSchool(school)
                            isSchoolSearchFocused = false
                        }
                        if index < results.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.gradelyTertiaryFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
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
                ManualStep(number: 1, text: String(localized: "schoolURL.manual.step1"))
                ManualStep(number: 2, text: String(localized: "schoolURL.manual.step2"))
                ManualStep(number: 3, text: String(localized: "schoolURL.manual.step3"))
                ManualStep(number: 4, text: String(localized: "schoolURL.manual.step4"))

                Text("schoolURL.manual.example")
                    .font(.caption.monospaced())
                    .foregroundStyle(Brand.primary)
                    .padding(.top, Spacing.xs)
            }
            .padding(.top, Spacing.sm)
        } label: {
            Label(String(localized: "schoolURL.manual.title"), systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
        }
        .tint(Brand.primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.gradelyTertiaryFill)
        )
        .accessibilityIdentifier("schoolURLManual")
    }

    private var eduPageURLHint: some View {
        Label(String(localized: "edupage.schoolURL.hint"), systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var twoFactorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(String(localized: "edupage.twoFactor.code"), text: $viewModel.twoFactorCode)
                        .gradelyKeyboardType(.numberPad)
                        .accessibilityIdentifier("eduPageTwoFactorCode")

                    Button(String(localized: "edupage.twoFactor.submit")) {
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
                Image(systemName: "building.columns.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.primary)
                    .frame(width: 28, height: 28)
                    .background(Brand.primary.opacity(0.13), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(school.trimmedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.xs) {
                        Text(school.trimmedTown)
                        Text("-")
                        Text(school.trimmedSchoolURL)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                Spacer(minLength: Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
