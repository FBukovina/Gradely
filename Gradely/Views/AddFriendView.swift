import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Adds a friend: their name, then their Bakaláři login, their class from the
/// school's public timetable, or a PDF or photo read on this device.
struct AddFriendView: View {
    let friends: FriendsViewModel
    var onAdded: (Friend) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddFriendViewModel
    @State private var isFileImporterPresented = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isPasswordVisible = false
    @FocusState private var isNameFocused: Bool

    init(friends: FriendsViewModel, onAdded: @escaping (Friend) -> Void = { _ in }) {
        self.friends = friends
        self.onAdded = onAdded
        _viewModel = State(initialValue: AddFriendViewModel(friends: friends))
    }

    var body: some View {
        ModalNavigationContainer {
            ZStack {
                SettingsBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        topBar
                        stepContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .settingsModalNavigationChrome()
        }
        .gradelyMacSheetSize(minWidth: 520, idealWidth: 600, minHeight: 560, idealHeight: 720)
        .animation(.easeOut(duration: 0.2), value: viewModel.step)
        .task { await viewModel.loadSchoolDirectoryIfNeeded() }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            Task { await readFile(at: url) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await viewModel.readDocument(data, fileName: nil)
                }
                photoItem = nil
            }
        }
        .accessibilityIdentifier("addFriendView")
    }

    private var topBar: some View {
        HStack {
            if viewModel.step != .method {
                Button {
                    viewModel.goBack()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        GradelyIcon("arrow-left-01", size: 14)
                        Text("action.back")
                    }
                    .font(.gradely(.subheadline).weight(.semibold))
                    .foregroundStyle(Brand.primary)
                    .frame(minHeight: ControlMetrics.minHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("addFriendBackButton")
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                GradelyModalCloseLabel()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(AppL10n.string("action.cancel"))
            .accessibilityIdentifier("modalDismissButton")
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .method: methodStep
        case .bakalari: bakalariStep
        case .publicClass: publicClassStep
        case .groups: groupsStep
        case .document: documentStep
        case .review:
            FriendImportReviewView(viewModel: viewModel) {
                if let friend = viewModel.finishImport() { complete(friend) }
            }
        }
    }

    // MARK: - Steps

    private var methodStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsModalFlowHero(title: "friends.add.title", message: "friends.add.message")

            TextField(AppL10n.string("friends.add.name"), text: $viewModel.name)
                .gradelyTextInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isNameFocused)
                .submitLabel(.done)
                .brandField()
                .accessibilityIdentifier("addFriendNameField")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                SettingsModalSectionHeader(title: "friends.add.how")
                SettingsSurface(padding: 0) {
                    VStack(spacing: 0) {
                        methodRow("friends.method.bakalari.title", message: "friends.method.bakalari.message", icon: "key-01", step: .bakalari)
                        SettingsRowDivider()
                        methodRow("friends.method.public.title", message: "friends.method.public.message", icon: "globe-02", step: .publicClass)
                        SettingsRowDivider()
                        methodRow("friends.method.document.title", message: "friends.method.document.message", icon: "legal-document-01", step: .document)
                    }
                }
                .disabled(viewModel.trimmedName.isEmpty)
                .opacity(viewModel.trimmedName.isEmpty ? 0.45 : 1)
            }
        }
        .onAppear { isNameFocused = viewModel.trimmedName.isEmpty }
    }

    private func methodRow(_ title: LocalizedStringKey, message: LocalizedStringKey, icon: String, step: AddFriendViewModel.Step) -> some View {
        Button {
            // Let the name field give up the keyboard before it leaves the
            // screen; otherwise the next step's first tap only closes it.
            isNameFocused = false
            Task { @MainActor in viewModel.choose(step) }
        } label: {
            HStack(spacing: Spacing.md) {
                SettingsIcon(name: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.gradely(.body).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsDisclosureIcon()
            }
            .padding(.horizontal, SettingsRowMetrics.inset)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addFriendMethod-\(String(describing: step))")
    }

    private var bakalariStep: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SettingsModalFlowHero(
                title: "friends.bakalari.title",
                message: LocalizedStringKey(String(format: AppL10n.string("friends.bakalari.message"), viewModel.trimmedName))
            )

            FriendSchoolField(viewModel: viewModel)

            // Not tagged .username/.password: this is the friend's login, so
            // AutoFill must neither suggest the user's own Bakaláři password
            // nor offer to save the friend's into the user's Passwords.
            TextField(AppL10n.string("login.username"), text: $viewModel.username)
                .gradelyTextInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .brandField()
                .accessibilityIdentifier("addFriendUsernameField")

            HStack(spacing: Spacing.sm) {
                Group {
                    if isPasswordVisible {
                        TextField(AppL10n.string("login.password"), text: $viewModel.password)
                    } else {
                        SecureField(AppL10n.string("login.password"), text: $viewModel.password)
                    }
                }
                .textContentType(.oneTimeCode)
                .gradelyTextInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await connectBakalari() } }
                .accessibilityIdentifier("addFriendPasswordField")

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

            errorText

            Button {
                Task { await connectBakalari() }
            } label: {
                progressLabel("friends.bakalari.connect")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isWorking || !viewModel.hasSchool || viewModel.username.isEmpty || viewModel.password.isEmpty)
            .accessibilityIdentifier("addFriendConnectButton")

            Text("friends.bakalari.privacy")
                .font(.gradely(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var publicClassStep: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SettingsModalFlowHero(title: "friends.public.title", message: "friends.public.message")

            FriendSchoolField(viewModel: viewModel)

            if viewModel.classes.isEmpty {
                errorText

                Button {
                    Task { await viewModel.loadClasses() }
                } label: {
                    progressLabel("friends.public.showClasses")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isWorking || !viewModel.hasSchool)
                .accessibilityIdentifier("addFriendShowClassesButton")
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SettingsModalSectionHeader(title: "friends.public.class")
                    errorText
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Spacing.sm)], spacing: Spacing.sm) {
                        ForEach(viewModel.classes) { schoolClass in
                            Button {
                                Task {
                                    if let friend = await viewModel.selectClass(schoolClass) { complete(friend) }
                                }
                            } label: {
                                Text(verbatim: schoolClass.name)
                                    .font(.gradely(.subheadline).weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: ControlMetrics.minHeight)
                            }
                            .buttonStyle(.bordered)
                            .tint(Brand.primary)
                            .disabled(viewModel.isWorking)
                            .accessibilityIdentifier("addFriendClass-\(schoolClass.id)")
                        }
                    }
                    if viewModel.isWorking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var groupsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SettingsModalFlowHero(
                title: "friends.groups.title",
                message: LocalizedStringKey(String(format: AppL10n.string("friends.groups.message"), viewModel.trimmedName))
            )

            SettingsSurface(padding: Spacing.md) {
                VStack(spacing: Spacing.sm) {
                    ForEach(viewModel.groups, id: \.self) { group in
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedGroups.contains(group) },
                            set: { isOn in
                                if isOn { viewModel.selectedGroups.insert(group) } else { viewModel.selectedGroups.remove(group) }
                            }
                        )) {
                            Text(verbatim: group)
                                .font(.gradely(.body))
                        }
                        .tint(Brand.primary)
                    }
                }
            }

            Button {
                if let friend = viewModel.finishPublic() { complete(friend) }
            } label: {
                Text("friends.add.save")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("addFriendSaveGroupsButton")
        }
    }

    private var documentStep: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SettingsModalFlowHero(title: "friends.document.title", message: "friends.document.message")

            errorText

            Button {
                isFileImporterPresented = true
            } label: {
                progressLabel("friends.document.chooseFile")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isWorking)
            .accessibilityIdentifier("addFriendChooseFileButton")

            PhotosPicker(selection: $photoItem, matching: .images) {
                PlainLinkLabel("friends.document.choosePhoto")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isWorking)
            .accessibilityIdentifier("addFriendChoosePhotoButton")

            Button {
                viewModel.startBlank()
            } label: {
                PlainLinkLabel("friends.document.typeIn")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isWorking)
            .accessibilityIdentifier("addFriendTypeInButton")

            Text("friends.document.privacy")
                .font(.gradely(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var errorText: some View {
        if let message = viewModel.errorMessage {
            Text(message)
                .font(.gradely(.subheadline))
                .foregroundStyle(Color.gradelySystemOrange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("addFriendError")
        }
    }

    private func progressLabel(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.sm) {
            if viewModel.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .tint(Brand.onAccent)
            }
            Text(title)
        }
    }

    private func connectBakalari() async {
        if let friend = await viewModel.connectBakalari() { complete(friend) }
    }

    private func readFile(at url: URL) async {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            viewModel.errorMessage = TimetableDocumentError.unreadable.errorDescription
            return
        }
        await viewModel.readDocument(data, fileName: url.lastPathComponent)
    }

    private func complete(_ friend: Friend) {
        friends.add(friend)
        onAdded(friend)
        dismiss()
    }
}

/// School search for the friend's school, with your own school picked first.
private struct FriendSchoolField: View {
    @Bindable var viewModel: AddFriendViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                GradelyIcon(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    AppL10n.string("schoolDirectory.search"),
                    text: Binding(get: { viewModel.schoolSearchText }, set: { viewModel.updateSchoolSearch($0) })
                )
                .gradelyTextInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isFocused)
                .accessibilityIdentifier("addFriendSchoolField")

                if viewModel.isSchoolDirectoryLoading {
                    ProgressView().controlSize(.small)
                } else if viewModel.hasSchool {
                    GradelyIcon(systemName: "checkmark.circle.fill", size: 16)
                        .foregroundStyle(Brand.primary)
                }
            }
            .brandField()

            let results = viewModel.schoolResults
            if !results.isEmpty || viewModel.typedSchoolAddress != nil {
                VStack(spacing: 0) {
                    ForEach(Array(results.prefix(6).enumerated()), id: \.element.id) { index, school in
                        if index > 0 { Divider() }
                        resultRow(title: school.trimmedName, subtitle: "\(school.trimmedTown) · \(school.trimmedSchoolURL)") {
                            viewModel.selectSchool(school)
                            isFocused = false
                        }
                    }
                    if results.isEmpty, let address = viewModel.typedSchoolAddress {
                        resultRow(title: String(format: AppL10n.string("friends.school.useAddress"), address), subtitle: nil) {
                            viewModel.useTypedSchool()
                            isFocused = false
                        }
                    }
                }
            }
        }
    }

    private func resultRow(title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.gradely(.subheadline).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
