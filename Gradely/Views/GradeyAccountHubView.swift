import SwiftUI

enum SettingsDestination: String, CaseIterable, Hashable, Identifiable {
    case account
    case connectedServices
    case notifications
    case privacyData
    case appPreferences
    case supportAbout

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .account: "settings.destination.account.title"
        case .connectedServices: "settings.destination.connected.title"
        case .notifications: "settings.destination.notifications.title"
        case .privacyData: "settings.destination.privacy.title"
        case .appPreferences: "settings.destination.preferences.title"
        case .supportAbout: "settings.destination.support.title"
        }
    }

    var localizedTitle: String {
        switch self {
        case .account: AppL10n.string("settings.destination.account.title")
        case .connectedServices: AppL10n.string("settings.destination.connected.title")
        case .notifications: AppL10n.string("settings.destination.notifications.title")
        case .privacyData: AppL10n.string("settings.destination.privacy.title")
        case .appPreferences: AppL10n.string("settings.destination.preferences.title")
        case .supportAbout: AppL10n.string("settings.destination.support.title")
        }
    }

    var subtitle: String {
        switch self {
        case .account: AppL10n.string("settings.destination.account.subtitle")
        case .connectedServices: AppL10n.string("settings.destination.connected.subtitle")
        case .notifications: AppL10n.string("settings.destination.notifications.subtitle")
        case .privacyData: AppL10n.string("settings.destination.privacy.subtitle")
        case .appPreferences: AppL10n.string("settings.destination.preferences.subtitle")
        case .supportAbout: AppL10n.string("settings.destination.support.subtitle")
        }
    }

    var hugeiconName: String {
        switch self {
        case .account: "user"
        case .connectedServices: "link-04"
        case .notifications: "notification-01"
        case .privacyData: "security-lock"
        case .appPreferences: "settings-02"
        case .supportAbout: "help-circle"
        }
    }
}

private enum SettingsRoute: Hashable {
    case detail(SettingsDestination)
    case schoolLink(reconnectAccountID: String?)
    case stravaCZLink
}

private enum SettingsConnectionRoute: Hashable {
    case schoolLink(reconnectAccountID: String?)
    case stravaCZLink
}

struct GradeyAccountHubView: View {
    let account: GradeyAccount?
    let isGuestMode: Bool
    let repository: SchoolRepository
    let stravaCZRepository: StravaCZRepository
    let schoolDirectoryProvider: any SchoolDirectoryProviding
    let supportTipProvider: any SupportTipProviding
    let notificationAuthorizer: any NotificationAuthorizing
    let onSchoolLinked: () -> Void
    let onSignedOut: () -> Void
    let onLeaveGuestMode: () -> Void
    let onAccountUpdated: (GradeyAccount) -> Void
    let onRestartOnboarding: (OnboardingJourney) -> Void
    let onDebugSignOut: () -> Void
    let onDebugClearCache: () -> Void
    let onDebugResetAsNewUser: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("settings.showMealsTab") private var showMealsTab = true
    @Bindable private var languageStore = AppLanguageStore.shared
    @AppStorage(GradeyDebugModeStore.storageKey) private var isDebugModeEnabled = false

    @State private var viewModel: GradeyAccountHubViewModel
    @State private var compactPath: [SettingsRoute] = []
    @State private var detailPath: [SettingsConnectionRoute] = []
    @State private var selectedDestination: SettingsDestination?
    @State private var pendingUnlinkAccount: LinkedAccount?
    @State private var isSupportSheetPresented = false
    @State private var isCreditsPresented = false
    @State private var isStudentPickerPresented = false
    @State private var studentSwitchError: String?
    @State private var retryingCloudLink: OnboardingWarning.Kind?
    @State private var notificationAuthorizationStatus: NotificationAuthorizationStatus = .notDetermined
    @State private var isSignOutConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isFinalDeleteConfirmationPresented = false
    @State private var isExporting = false
    @State private var exportedDataURL: URL?
    @State private var isDeletingAccount = false
    @State private var actionErrorMessage: String?
    @State private var shouldFocusFullName = false
    @FocusState private var isFullNameFieldFocused: Bool
    @State private var versionTapCount = 0

    init(
        account: GradeyAccount?,
        isGuestMode: Bool = false,
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        linkedAccountRepository: LinkedAccountRepository,
        notificationClient: any DevicePushTokenClient,
        authClient: any GradeyAuthClient,
        preferencesStore: MarkNotificationSettingsStore,
        supportTipProvider: any SupportTipProviding,
        notificationAuthorizer: any NotificationAuthorizing,
        onSchoolLinked: @escaping () -> Void,
        onSignedOut: @escaping () -> Void,
        onLeaveGuestMode: @escaping () -> Void = {},
        onAccountUpdated: @escaping (GradeyAccount) -> Void = { _ in },
        onRestartOnboarding: @escaping (OnboardingJourney) -> Void = { _ in },
        onDebugSignOut: @escaping () -> Void = {},
        onDebugClearCache: @escaping () -> Void = {},
        onDebugResetAsNewUser: @escaping () -> Void = {}
    ) {
        self.account = account
        self.isGuestMode = isGuestMode
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.supportTipProvider = supportTipProvider
        self.notificationAuthorizer = notificationAuthorizer
        self.onSchoolLinked = onSchoolLinked
        self.onSignedOut = onSignedOut
        self.onLeaveGuestMode = onLeaveGuestMode
        self.onAccountUpdated = onAccountUpdated
        self.onRestartOnboarding = onRestartOnboarding
        self.onDebugSignOut = onDebugSignOut
        self.onDebugClearCache = onDebugClearCache
        self.onDebugResetAsNewUser = onDebugResetAsNewUser
        _selectedDestination = State(initialValue: .account)
        _viewModel = State(initialValue: GradeyAccountHubViewModel(
            account: account,
            linkedAccountRepository: linkedAccountRepository,
            notificationClient: notificationClient,
            authClient: authClient,
            preferencesStore: preferencesStore
        ))
    }

    var body: some View {
        adaptiveLayout
            .environment(\.locale, languageStore.locale)
            .alert("gradey.account.title", isPresented: errorBinding) {
                Button("action.ok", role: .cancel) {
                    viewModel.clearError()
                    actionErrorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? actionErrorMessage ?? "")
            }
            .confirmationDialog(
                "gradey.account.unlink.title",
                isPresented: unlinkDialogBinding,
                titleVisibility: .visible
            ) {
                if let pendingUnlinkAccount {
                    Button("gradey.account.unlink.confirm", role: .destructive) {
                        unlink(pendingUnlinkAccount)
                    }
                    .accessibilityIdentifier("accountUnlinkConfirmButton")
                }

                Button("action.cancel", role: .cancel) {
                    pendingUnlinkAccount = nil
                }
                .accessibilityIdentifier("accountUnlinkCancelButton")
            } message: {
                Text(unlinkMessage)
            }
            .alert(
                isGuestMode
                    ? "settings.account.signOut.guest.title"
                    : "settings.account.signOut.confirm.title",
                isPresented: $isSignOutConfirmationPresented
            ) {
                Button(
                    isGuestMode ? "gradey.guest.schoolLogout" : "action.logout",
                    role: .destructive
                ) {
                    completeSignOut()
                }
                .accessibilityIdentifier("accountSignOutConfirmButton")

                Button("action.cancel", role: .cancel) {}
                    .accessibilityIdentifier("accountSignOutCancelButton")
            } message: {
                Text(
                    isGuestMode
                        ? "settings.account.signOut.guest.message"
                        : "settings.account.signOut.confirm.message"
                )
            }
            .confirmationDialog(
                "settings.privacy.delete.first.title",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("settings.privacy.delete.first.action", role: .destructive) {
                    isFinalDeleteConfirmationPresented = true
                }
                .accessibilityIdentifier("accountDeleteFirstConfirmButton")

                Button("action.cancel", role: .cancel) {}
                    .accessibilityIdentifier("accountDeleteFirstCancelButton")
            } message: {
                Text("settings.privacy.delete.first.message")
            }
            .alert(
                "settings.privacy.delete.final.title",
                isPresented: $isFinalDeleteConfirmationPresented
            ) {
                Button("settings.privacy.delete.final.action", role: .destructive) {
                    deleteGradeyAccount()
                }
                .accessibilityIdentifier("accountDeleteFinalConfirmButton")

                Button("action.cancel", role: .cancel) {}
                    .accessibilityIdentifier("accountDeleteFinalCancelButton")
            } message: {
                Text("settings.privacy.delete.final.message")
            }
            .sheet(isPresented: $isSupportSheetPresented) {
                SupportTipView(
                    viewModel: SupportTipViewModel(
                        supportTipProvider: supportTipProvider,
                        isSignedIn: account != nil
                    )
                )
            }
            .sheet(isPresented: $isCreditsPresented) {
                CreditsView()
            }
            .sheet(isPresented: $isStudentPickerPresented) {
                studentPicker
            }
            .alert(AppL10n.string("error.title"), isPresented: Binding(
                get: { studentSwitchError != nil },
                set: { if !$0 { studentSwitchError = nil } }
            )) {
                Button(AppL10n.string("action.ok"), role: .cancel) {
                    studentSwitchError = nil
                }
            } message: {
                Text(studentSwitchError ?? "")
            }
            .task {
                if let refreshedAccount = await viewModel.refresh() {
                    onAccountUpdated(refreshedAccount)
                }
                await refreshNotificationAuthorization()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await refreshNotificationAuthorization()
                }
            }
    }

    @ViewBuilder
    private var adaptiveLayout: some View {
        #if os(macOS)
        splitLayout
        #else
        if horizontalSizeClass == .regular {
            splitLayout
        } else {
            compactLayout
        }
        #endif
    }

    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            overview(selectedDestination: nil) { destination in
                select(destination) {
                    compactPath.append(.detail(destination))
                }
            }
            .settingsRootNavigationChrome()
            .navigationDestination(for: SettingsRoute.self) { route in
                compactRoute(route)
            }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            overview(selectedDestination: selectedDestination) { destination in
                select(destination) {
                    selectedDestination = destination
                    detailPath = []
                }
            }
            .settingsRootNavigationChrome()
            .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 480)
        } detail: {
            NavigationStack(path: $detailPath) {
                if let selectedDestination {
                    detailPage(selectedDestination)
                        .navigationTitle(selectedDestination.title)
                        .gradelyNavigationTitleDisplayMode(.inline)
                        .navigationDestination(for: SettingsConnectionRoute.self) { route in
                            splitConnectionRoute(route)
                        }
                } else {
                    ContentUnavailableView {
                        Label {
                            Text("settings.detail.select.title")
                        } icon: {
                            SettingsHugeIcon(
                                iconName: "gears",
                                size: 28,
                                color: .secondary
                            )
                        }
                    } description: {
                        Text("settings.detail.select.message")
                    }
                    .gradelyScreenBackground()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func compactRoute(_ route: SettingsRoute) -> some View {
        switch route {
        case .detail(let destination):
            detailPage(destination)
                .navigationTitle(destination.title)
                .gradelyNavigationTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            if !compactPath.isEmpty {
                                compactPath.removeLast()
                            }
                        } label: {
                            SettingsHugeIcon(
                                iconName: "arrow-left-01",
                                size: 18,
                                color: .primary
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppL10n.string("settings.back"))
                        .accessibilityIdentifier("settingsBackButton")
                    }
                }
        case .schoolLink(let reconnectAccountID):
            schoolConnectionView(reconnectAccountID: reconnectAccountID)
        case .stravaCZLink:
            stravaConnectionView
        }
    }

    @ViewBuilder
    private func splitConnectionRoute(_ route: SettingsConnectionRoute) -> some View {
        switch route {
        case .schoolLink(let reconnectAccountID):
            schoolConnectionView(reconnectAccountID: reconnectAccountID)
        case .stravaCZLink:
            stravaConnectionView
        }
    }

    private func overview(
        selectedDestination: SettingsDestination?,
        onSelect: @escaping (SettingsDestination) -> Void
    ) -> some View {
        ZStack {
            SettingsScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        settingsHeader

                        profileSummary(
                            isSelected: selectedDestination == .account,
                            onSelect: { onSelect(.account) }
                        )
                    }

                    SettingsOverviewGroup {
                        overviewRow(
                            .connectedServices,
                            selectedDestination: selectedDestination,
                            onSelect: onSelect
                        )
                        SettingsRowDivider()
                        overviewRow(
                            .notifications,
                            selectedDestination: selectedDestination,
                            onSelect: onSelect
                        )
                        SettingsRowDivider()
                        overviewRow(
                            .privacyData,
                            selectedDestination: selectedDestination,
                            onSelect: onSelect
                        )
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SectionHeader("settings.group.app")
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 4)

                        SettingsOverviewGroup {
                            overviewRow(
                                .appPreferences,
                                selectedDestination: selectedDestination,
                                onSelect: onSelect
                            )
                            SettingsRowDivider()
                            overviewRow(
                                .supportAbout,
                                selectedDestination: selectedDestination,
                                onSelect: onSelect
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, Spacing.xxl)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("accountHubScroll")
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Text("settings.title")
                .font(.gradelyDisplay(size: 36))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Spacing.md)

            Button {
                dismiss()
            } label: {
                SettingsCloseLabel()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppL10n.string("action.done"))
            .accessibilityIdentifier("settingsDoneButton")
        }
        .accessibilitySortPriority(10)
    }

    private func profileSummary(
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            AdaptiveSettingsStack {
                AccountAvatar(
                    name: profileAvatarName,
                    avatarURL: viewModel.account?.avatarURL,
                    size: 60
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(profileDisplayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(profileSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(Brand.primary.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SettingsDisclosureIcon()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.xl - 4, style: .continuous)
                        .fill(Brand.primary.opacity(0.10))
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            SettingsSurfaceShape()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settingsDestination-account")
    }

    private func select(
        _ destination: SettingsDestination,
        selection: () -> Void
    ) {
        if destination == .account, !isGuestMode, !hasFullName {
            shouldFocusFullName = true
        }
        selection()
    }

    private func overviewRow(
        _ destination: SettingsDestination,
        selectedDestination: SettingsDestination?,
        onSelect: @escaping (SettingsDestination) -> Void
    ) -> some View {
        let status = overviewStatus(for: destination)

        return SettingsOverviewRow(
            destination: destination,
            subtitle: overviewSubtitle(for: destination),
            statusIconName: status?.iconName,
            statusColor: status?.color ?? Brand.primary,
            statusAccessibilityLabel: status?.accessibilityLabel,
            isSelected: selectedDestination == destination,
            onSelect: { onSelect(destination) }
        )
        .accessibilityIdentifier("settingsDestination-\(destination.rawValue)")
    }

    private func overviewSubtitle(for destination: SettingsDestination) -> String {
        switch destination {
        case .account:
            return destination.subtitle
        case .connectedServices:
            let school: String
            if schoolAccounts.isEmpty {
                school = AppL10n.string("settings.overview.school.notConnected")
            } else if schoolAccounts.contains(where: accountNeedsAttention) {
                school = "\(AppL10n.string("settings.connected.school.title")): \(AppL10n.string("gradey.account.status.actionRequired"))"
            } else {
                school = AppL10n.string("settings.overview.school.active")
            }

            let meals: String
            if canteenAccounts.isEmpty {
                meals = AppL10n.string("settings.overview.canteen.notConnected")
            } else if canteenAccounts.contains(where: accountNeedsAttention) {
                meals = "\(AppL10n.string("settings.connected.canteen.title")): \(AppL10n.string("gradey.account.status.actionRequired"))"
            } else {
                meals = AppL10n.string("settings.overview.canteen.connected")
            }
            return "\(school) · \(meals)"
        case .notifications:
            guard notificationsAreAvailable else {
                return AppL10n.string("settings.overview.notifications.unavailable")
            }
            guard viewModel.notificationPreferences.newMarksEnabled else {
                return AppL10n.string("settings.overview.notifications.off")
            }
            if viewModel.notificationPreferences.quietHoursEnabled {
                return String(
                    format: AppL10n.string("settings.overview.notifications.quietUntil"),
                    formattedMinute(viewModel.notificationPreferences.quietHoursEndMinute)
                )
            }
            return AppL10n.string("settings.overview.notifications.on")
        case .privacyData:
            return destination.subtitle
        case .appPreferences:
            return languageStore.selection.displayName
        case .supportAbout:
            return destination.subtitle
        }
    }

    private func overviewStatus(
        for destination: SettingsDestination
    ) -> (iconName: String, color: Color, accessibilityLabel: String)? {
        switch destination {
        case .connectedServices:
            if viewModel.accounts.contains(where: accountNeedsAttention) {
                return (
                    "alert-circle",
                    .gradelySystemOrange,
                    AppL10n.string("gradey.account.status.actionRequired")
                )
            }
            return nil
        default:
            return nil
        }
    }

    private func accountNeedsAttention(_ account: LinkedAccount) -> Bool {
        account.status == .actionRequired || account.status == .failed
    }
}

// MARK: - Detail destinations

private extension GradeyAccountHubView {
    func detailPage(_ destination: SettingsDestination) -> some View {
        ZStack {
            SettingsScreenBackground()

            ScrollView {
                detailContent(destination)
                    .padding(.horizontal, 20)
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.xxl)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("settingsDetail-\(destination.rawValue)")
    }

    @ViewBuilder
    func detailContent(_ destination: SettingsDestination) -> some View {
        switch destination {
        case .account:
            accountDetail
        case .connectedServices:
            connectedServicesDetail
        case .notifications:
            notificationsDetail
        case .privacyData:
            privacyDataDetail
        case .appPreferences:
            appPreferencesDetail
        case .supportAbout:
            supportAboutDetail
        }
    }

    var accountDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(
                title: "settings.account.profile.title",
                message: "settings.account.profile.message"
            )

            SettingsSurface {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    AdaptiveSettingsStack {
                        AccountAvatar(
                            name: profileAvatarName,
                            avatarURL: viewModel.account?.avatarURL,
                            size: 72
                        )

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(profileDisplayName)
                                .font(.title3.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(profileSubtitle)
                                .font(.body)
                                .foregroundStyle(Brand.primary.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !isGuestMode {
                        Divider()

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("settings.account.name.title")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            TextField(
                                "settings.account.name.placeholder",
                                text: Binding(
                                    get: { viewModel.fullNameDraft },
                                    set: viewModel.updateFullNameDraft
                                )
                            )
                            .focused($isFullNameFieldFocused)
                            .gradelyTextInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .padding(.horizontal, Spacing.md)
                            .frame(minHeight: 48)
                            .background(
                                Color.gradelyTertiaryFill,
                                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(
                                        isFullNameFieldFocused
                                            ? Brand.primary.opacity(0.65)
                                            : Color.primary.opacity(0.06),
                                        lineWidth: isFullNameFieldFocused ? 1.5 : 1
                                    )
                            }
                            .onSubmit {
                                guard viewModel.canSaveFullName else { return }
                                saveFullName()
                            }
                            .accessibilityIdentifier("accountFullNameField")

                            if viewModel.trimmedFullName.count > 80 {
                                SettingsHugeiconLabel(
                                    "settings.account.name.tooLong",
                                    iconName: "alert-circle",
                                    iconColor: .red
                                )
                                .font(.caption)
                                .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("accountFullNameValidationError")
                            } else if let fullNameErrorMessage = viewModel.fullNameErrorMessage {
                                SettingsHugeiconLabel(
                                    verbatim: fullNameErrorMessage,
                                    iconName: "alert-circle",
                                    iconColor: .red
                                )
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("accountFullNameSaveError")
                            } else {
                                Text("settings.account.name.caption")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button {
                                saveFullName()
                            } label: {
                                if viewModel.isUpdatingFullName {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 44)
                                } else {
                                    Text("settings.account.name.save")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 44)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.primary)
                            .disabled(!viewModel.canSaveFullName)
                            .accessibilityIdentifier("accountFullNameSaveButton")
                        }

                        Divider()

                        SettingsValueRow(
                            title: "settings.account.appleID.title",
                            value: viewModel.account?.email
                                ?? AppL10n.string("gradey.account.appleConnected")
                        )
                        .accessibilityIdentifier("accountAppleIDValue")
                    }

                    if repository.availableStudents.count > 1 {
                        Divider()

                        Button {
                            isStudentPickerPresented = true
                        } label: {
                            SettingsActionRow(
                                title: "edupage.children.switch",
                                message: "settings.account.children.message",
                                iconName: "students"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("switchEduPageStudentButton")
                    }
                }
            }
            .onAppear {
                focusFullNameIfRequested()
            }
            .onChange(of: shouldFocusFullName) { _, shouldFocus in
                guard shouldFocus else { return }
                focusFullNameIfRequested()
            }

            if isGuestMode {
                DetailSectionHeader(
                    title: "gradey.guest.accountSection.title",
                    message: "gradey.guest.accountSection.message"
                )

                SettingsSurface {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SettingsHugeiconLabel(
                            "gradey.guest.accountSection.heading",
                            iconName: "user-add-02"
                        )
                            .font(.headline)

                        Button {
                            dismiss()
                            onLeaveGuestMode()
                        } label: {
                            SettingsHugeiconLabel(
                                "gradey.guest.accountSection.action",
                                iconName: "user-check-02",
                                iconColor: Brand.onAccent
                            )
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.primary)
                        .controlSize(.large)
                        .accessibilityIdentifier("leaveGuestModeButton")
                    }
                }
            }

            DetailSectionHeader(
                title: "settings.account.session.title",
                message: isGuestMode
                    ? "settings.account.session.guestMessage"
                    : "settings.account.session.message"
            )

            Button(role: .destructive) {
                isSignOutConfirmationPresented = true
            } label: {
                SettingsHugeiconLabel(
                    accountSignOutTitle,
                    iconName: "logout-01",
                    iconColor: .red
                )
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityIdentifier("accountSignOutButton")

            if !isGuestMode {
                DetailSectionHeader(
                    title: "settings.privacy.delete.title",
                    message: "settings.privacy.delete.message"
                )

                deleteGradeyAccountButton
            }
        }
    }

    var connectedServicesDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(
                title: "settings.connected.school.title",
                message: "settings.connected.school.message"
            )

            if isSchoolCloudLinkMissing {
                cloudLinkWarning(
                    kind: .schoolCloudLink,
                    message: "onboarding.sync.warning.school"
                ) {
                    await retrySchoolCloudLink()
                }
            }

            if schoolAccounts.isEmpty {
                EmptyServiceCard(
                    title: "settings.connected.school.empty.title",
                    message: isGuestMode
                        ? "settings.connected.school.guest.message"
                        : "settings.connected.school.empty.message",
                    iconName: "school"
                )

                Button {
                    openSchoolConnection(reconnectAccountID: nil)
                } label: {
                    SettingsHugeiconLabel(
                        "gradey.account.linkSchool.title",
                        iconName: "link-04",
                        iconColor: Brand.onAccent
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isGuestMode)
                .accessibilityIdentifier("accountLinkSchoolButton")
            } else {
                ForEach(schoolAccounts) { linkedAccount in
                    connectedAccountCard(linkedAccount)
                }

                Button {
                    openSchoolConnection(reconnectAccountID: nil)
                } label: {
                    SettingsHugeiconLabel(
                        "settings.connected.school.addAnother",
                        iconName: "add-01",
                        iconColor: Brand.primary
                    )
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Brand.primary)
                .disabled(isGuestMode)
                .accessibilityIdentifier("accountLinkSchoolButton")
            }

            DetailSectionHeader(
                title: "settings.connected.canteen.title",
                message: "settings.connected.canteen.message"
            )

            if isMealsCloudLinkMissing {
                cloudLinkWarning(
                    kind: .mealsCloudLink,
                    message: "onboarding.sync.warning.meals"
                ) {
                    await retryMealsCloudLink()
                }
            }

            if canteenAccounts.isEmpty {
                EmptyServiceCard(
                    title: "settings.connected.canteen.empty.title",
                    message: isGuestMode
                        ? "settings.connected.canteen.guest.message"
                        : "settings.connected.canteen.empty.message",
                    iconName: "restaurant-02"
                )

                Button {
                    openStravaConnection()
                } label: {
                    SettingsHugeiconLabel(
                        "gradey.account.linkStrava.title",
                        iconName: "link-04",
                        iconColor: Brand.onAccent
                    )
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.primary)
                .disabled(isGuestMode)
                .accessibilityIdentifier("accountLinkStravaCZButton")
            } else {
                ForEach(canteenAccounts) { linkedAccount in
                    connectedAccountCard(linkedAccount)
                }
            }

            if isGuestMode {
                SettingsAvailabilityMessage("settings.connected.guest.explanation")
            }
        }
    }

    func connectedAccountCard(_ linkedAccount: LinkedAccount) -> some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                AdaptiveSettingsStack {
                    SettingsIcon(
                        iconName: linkedAccount.provider.isSchoolProvider ? "school" : "restaurant-02"
                    )

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(linkedAccount.displayName)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("linkedAccountRow-\(linkedAccount.id)")

                        Text(linkedAccount.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    StatusChip(
                        text: linkedAccount.status.displayName,
                        color: linkedAccount.status == .active ? Brand.primary : .gradelySystemOrange
                    )
                }

                if let actionRequiredReason = linkedAccount.actionRequiredReason,
                   !actionRequiredReason.isEmpty {
                    Label {
                        Text(actionRequiredReason)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        SettingsHugeIcon(
                            iconName: "alert-02",
                            size: 14,
                            color: .gradelySystemOrange
                        )
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.gradelySystemOrange)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let lastSyncedAt = linkedAccount.lastSyncedAt {
                        SettingsMetadataRow(
                            title: "settings.connected.lastSync",
                            value: lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }

                    if let lastPolledAt = linkedAccount.lastPolledAt {
                        SettingsMetadataRow(
                            title: "settings.connected.lastChecked",
                            value: lastPolledAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }

                if linkedAccount.provider.isSchoolProvider {
                    Divider()

                    Toggle(isOn: Binding(
                        get: {
                            viewModel.accounts.first(where: { $0.id == linkedAccount.id })?.notificationsEnabled
                                ?? linkedAccount.notificationsEnabled
                        },
                        set: { enabled in
                            Task {
                                await viewModel.setNotificationsEnabled(enabled, for: linkedAccount)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("settings.connected.accountNotifications.title")
                            Text("settings.connected.accountNotifications.message")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Brand.primary)
                    .disabled(
                        isGuestMode
                            || viewModel.isMutating(linkedAccount)
                            || !viewModel.notificationPreferences.newMarksEnabled
                    )
                    .accessibilityIdentifier("linkedAccountNotificationsToggle-\(linkedAccount.id)")
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.sm) {
                        connectedAccountActions(linkedAccount)
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        connectedAccountActions(linkedAccount)
                    }
                }
            }
        }
        .disabled(viewModel.isMutating(linkedAccount))
        .overlay {
            if viewModel.isMutating(linkedAccount) {
                ProgressView()
                    .padding(Spacing.lg)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
    }

    @ViewBuilder
    func connectedAccountActions(_ linkedAccount: LinkedAccount) -> some View {
        if linkedAccount.provider.isSchoolProvider,
           viewModel.activeSchoolAccountID != linkedAccount.id {
            Button {
                activate(linkedAccount)
            } label: {
                SettingsHugeiconLabel(
                    "settings.connected.activate",
                    iconName: "checkmark-circle-02",
                    iconColor: Brand.onAccent
                )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.primary)
            .accessibilityIdentifier("linkedAccountActivate-\(linkedAccount.id)")
        }

        if linkedAccount.provider.isSchoolProvider,
           linkedAccount.status == .actionRequired || linkedAccount.status == .failed {
            Button {
                openSchoolConnection(reconnectAccountID: linkedAccount.id)
            } label: {
                SettingsHugeiconLabel(
                    "settings.connected.reconnect",
                    iconName: "refresh-04",
                    iconColor: Brand.primary
                )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Brand.primary)
            .accessibilityIdentifier("linkedAccountReconnect-\(linkedAccount.id)")
        }

        Button(role: .destructive) {
            pendingUnlinkAccount = linkedAccount
        } label: {
            SettingsHugeiconLabel(
                "gradey.account.unlink.action",
                iconName: "delete-02",
                iconColor: .red
            )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityIdentifier("linkedAccountUnlinkAction-\(linkedAccount.id)")
    }

    var notificationsDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(
                title: "settings.notifications.device.title",
                message: "settings.notifications.device.message"
            )

            SettingsSurface {
                AdaptiveSettingsStack {
                    SettingsIcon(iconName: notificationPermissionIconName)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("settings.notifications.permission.title")
                            .font(.headline)
                        Text(notificationPermissionLabel)
                            .font(.subheadline)
                            .foregroundStyle(notificationPermissionColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if notificationAuthorizationStatus != .authorized {
                        Button(notificationPermissionActionTitle) {
                            Task {
                                await resolveNotificationPermission()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(Brand.primary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("notificationPermissionAction")
                    }
                }
            }

            DetailSectionHeader(
                title: "gradey.account.notifications.title",
                message: "gradey.account.notifications.message"
            )

            SettingsSurface {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Toggle(isOn: Binding(
                        get: { viewModel.notificationPreferences.newMarksEnabled },
                        set: { enabled in
                            Task {
                                await setNotificationsEnabled(enabled)
                            }
                        }
                    )) {
                        Text("gradey.account.notifications.toggle")
                    }
                    .tint(Brand.primary)
                    .disabled(!notificationsAreAvailable)
                    .accessibilityIdentifier("newMarkNotificationsToggle")

                    Divider()

                    Picker("gradey.account.notifications.lockScreen", selection: Binding(
                        get: { viewModel.notificationPreferences.lockScreenDetail },
                        set: { detail in
                            updateNotificationPreferences { preferences in
                                preferences.lockScreenDetail = detail
                            }
                        }
                    )) {
                        Text("gradey.account.notifications.privateSummary")
                            .tag(NotificationLockScreenDetail.privateSummary)
                        Text("gradey.account.notifications.markAndSubject")
                            .tag(NotificationLockScreenDetail.markAndSubject)
                        Text("gradey.account.notifications.fullDetails")
                            .tag(NotificationLockScreenDetail.fullDetails)
                    }
                    .pickerStyle(.menu)
                    .disabled(!notificationControlsAreEnabled)
                    .accessibilityIdentifier("lockScreenDetailPicker")

                    Text(lockScreenDetailSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("lockScreenDetailSummary")
                }
            }

            DetailSectionHeader(
                title: "settings.notifications.quietHours.title",
                message: "settings.notifications.quietHours.message"
            )

            SettingsSurface {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Toggle(isOn: Binding(
                        get: { viewModel.notificationPreferences.quietHoursEnabled },
                        set: { enabled in
                            updateNotificationPreferences { preferences in
                                preferences.quietHoursEnabled = enabled
                            }
                        }
                    )) {
                        Text("settings.notifications.quietHours.toggle")
                    }
                    .tint(Brand.primary)
                    .disabled(!notificationControlsAreEnabled)
                    .accessibilityIdentifier("quietHoursToggle")

                    Divider()

                    DatePicker(
                        "settings.notifications.quietHours.start",
                        selection: quietTimeBinding(\.quietHoursStartMinute),
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!quietHoursControlsAreEnabled)
                    .accessibilityIdentifier("quietHoursStartPicker")

                    DatePicker(
                        "settings.notifications.quietHours.end",
                        selection: quietTimeBinding(\.quietHoursEndMinute),
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!quietHoursControlsAreEnabled)
                    .accessibilityIdentifier("quietHoursEndPicker")

                    Label {
                        Text(
                            String(
                                format: AppL10n.string("settings.notifications.timeZone"),
                                viewModel.notificationPreferences.quietHoursTimeZoneIdentifier
                            )
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        SettingsHugeIcon(
                            iconName: "globe-02",
                            size: 13,
                            color: .secondary
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let notificationsUnavailableMessage {
                SettingsAvailabilityMessage(notificationsUnavailableMessage)
                    .accessibilityIdentifier("settingsNotificationsUnavailableExplanation")
            }
        }
    }

    var privacyDataDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(
                title: "settings.privacy.documents.title",
                message: "settings.privacy.documents.message"
            )

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    legalSettingsRow(
                        title: "legal.privacyPolicy",
                        message: "settings.privacy.policy.caption",
                        iconName: "security-lock",
                        url: AppLinks.privacyPolicyURL,
                        accessibilityIdentifier: "privacyPolicyLink"
                    )

                    SettingsRowDivider()

                    legalSettingsRow(
                        title: "legal.termsOfUse",
                        message: "settings.privacy.terms.caption",
                        iconName: "left-to-right-list-bullet",
                        url: AppLinks.termsOfUseURL,
                        accessibilityIdentifier: "termsOfUseLink"
                    )
                }
            }

            DetailSectionHeader(
                title: "settings.privacy.age.title",
                message: "settings.privacy.age.message"
            )

            SettingsAvailabilityMessage(ageAttestationStatusMessage)
                .accessibilityIdentifier("settingsPrivacyAgeStatus")

            #if os(iOS)
            SettingsAvailabilityMessage("settings.privacy.intercom.note")
                .accessibilityIdentifier("settingsPrivacyIntercomNote")
            #endif

            DetailSectionHeader(
                title: "settings.privacy.export.title",
                message: "settings.privacy.export.message"
            )

            SettingsSurface {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SettingsActionRow(
                        title: "settings.privacy.export.action",
                        message: "settings.privacy.export.caption",
                        iconName: "file-export"
                    )

                    Button {
                        exportGradeyData()
                    } label: {
                        if isExporting || viewModel.isExporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                        } else {
                            SettingsHugeiconLabel(
                                "settings.privacy.export.prepare",
                                iconName: "file-export",
                                iconColor: Brand.onAccent
                            )
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.primary)
                    .disabled(isGuestMode || isExporting || viewModel.isExporting)
                    .accessibilityIdentifier("accountExportButton")

                    if let exportedDataURL {
                        ShareLink(item: exportedDataURL) {
                            SettingsHugeiconLabel(
                                "settings.privacy.export.share",
                                iconName: "share-03",
                                iconColor: Brand.primary
                            )
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(Brand.primary)
                        .accessibilityIdentifier("accountExportShareButton")
                    }
                }
            }

            DetailSectionHeader(
                title: "settings.privacy.delete.title",
                message: "settings.privacy.delete.message"
            )

            SettingsSurface {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Label {
                        Text("settings.privacy.delete.caption")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        SettingsHugeIcon(
                            iconName: "alert-02",
                            size: 14,
                            color: .gradelySystemOrange
                        )
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.gradelySystemOrange)

                    deleteGradeyAccountButton
                }
            }

            if isGuestMode {
                SettingsAvailabilityMessage("settings.privacy.guest.explanation")
            }
        }
    }

    var appPreferencesDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(
                title: "settings.destination.preferences.title",
                message: "settings.language.message"
            )

            AppLanguageOptionsList(store: languageStore, usesSettingsChrome: true)

            SettingsSurface {
                Toggle(isOn: $showMealsTab) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("settings.showMealsTab")
                            .font(.body.weight(.medium))
                        Text("settings.showMealsTab.message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Brand.primary)
                .accessibilityIdentifier("showMealsTabToggle")
            }
        }
    }

    var supportAboutDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(
                title: "settings.support.title",
                message: "settings.support.message"
            )

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    #if os(iOS)
                    Button(action: IntercomIdentity.presentMessenger) {
                        SettingsActionRow(
                            title: "settings.support.chat",
                            message: "settings.support.chat.message",
                            iconName: "message-multiple-01"
                        )
                        .padding(20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("supportChatButton")

                    SettingsRowDivider()
                    #endif

                    Button {
                        isSupportSheetPresented = true
                    } label: {
                        SettingsActionRow(
                            title: "support.tips.menu",
                            message: "support.tips.message",
                            iconName: "favourite"
                        )
                        .padding(20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("supportGradelyButton")

                    SettingsRowDivider()

                    Link(destination: AppLinks.filipEmailURL) {
                        SettingsActionRow(
                            title: "settings.support.contact",
                            message: "filip@openside.tech",
                            iconName: "mail-01"
                        )
                        .padding(20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("developerContactLink")

                    SettingsRowDivider()

                    Link(destination: AppLinks.githubRepositoryURL) {
                        SettingsActionRow(
                            title: "github.repository",
                            message: "settings.support.github.message",
                            iconName: "github-01"
                        )
                        .padding(20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("githubRepositoryLink")

                    SettingsRowDivider()

                    legalSettingsRow(
                        title: "legal.privacyPolicy",
                        message: "settings.privacy.policy.caption",
                        iconName: "security-lock",
                        url: AppLinks.privacyPolicyURL,
                        accessibilityIdentifier: "aboutPrivacyPolicyLink"
                    )

                    SettingsRowDivider()

                    legalSettingsRow(
                        title: "legal.termsOfUse",
                        message: "settings.privacy.terms.caption",
                        iconName: "left-to-right-list-bullet",
                        url: AppLinks.termsOfUseURL,
                        accessibilityIdentifier: "aboutTermsOfUseLink"
                    )
                }
            }

            DetailSectionHeader(
                title: "settings.about.title",
                message: "settings.about.message"
            )

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    Button {
                        isCreditsPresented = true
                    } label: {
                        SettingsActionRow(
                            title: "credits.title",
                            message: "settings.about.credits.message",
                            iconName: "user-group"
                        )
                        .padding(20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsCreditsButton")

                    SettingsRowDivider()

                    Button {
                        unlockDebugModeIfNeeded()
                    } label: {
                        SettingsValueRow(
                            title: "settings.about.version",
                            value: appVersion
                        )
                        .padding(20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsVersionRow")

                    SettingsRowDivider()

                    SettingsValueRow(
                        title: "settings.about.build",
                        value: appBuild
                    )
                    .padding(20)
                }
            }

            if isDebugModeEnabled {
                GradeyDebugPanel(
                    snapshot: GradeyDebugSnapshot.make(
                        supabaseUserID: viewModel.account?.id ?? account?.id,
                        linkedAccountID: (try? repository.currentStoredSession())?.linkedAccountID,
                        isGuestMode: isGuestMode
                    ),
                    onRestart: { journey in
                        dismiss()
                        onRestartOnboarding(journey)
                    },
                    onSignOut: {
                        dismiss()
                        onDebugSignOut()
                    },
                    onClearCache: onDebugClearCache,
                    onResetAsNewUser: {
                        dismiss()
                        onDebugResetAsNewUser()
                    },
                    onDisable: {
                        isDebugModeEnabled = false
                    }
                )
            }
        }
    }
}

// MARK: - State and actions

private extension GradeyAccountHubView {
    var profileDisplayName: String {
        if isGuestMode {
            return AppL10n.string("gradey.guest.profile.title")
        }
        if let fullName = viewModel.account?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullName.isEmpty {
            return fullName
        }
        return AppL10n.string("settings.profile.addName.title")
    }

    var hasFullName: Bool {
        guard let fullName = viewModel.account?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !fullName.isEmpty
    }

    var profileAvatarName: String {
        isGuestMode || hasFullName ? profileDisplayName : ""
    }

    var accountSignOutTitle: LocalizedStringKey {
        isGuestMode ? "gradey.guest.schoolLogout" : "action.logout"
    }

    var deleteGradeyAccountButton: some View {
        Button(role: .destructive) {
            isDeleteConfirmationPresented = true
        } label: {
            if isDeletingAccount || viewModel.isDeletingAccount {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            } else {
                SettingsHugeiconLabel(
                    "settings.privacy.delete.action",
                    iconName: "delete-02",
                    iconColor: .red
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(isGuestMode || isDeletingAccount || viewModel.isDeletingAccount)
        .accessibilityIdentifier("accountDeleteButton")
    }

    var profileSubtitle: String {
        if isGuestMode {
            return AppL10n.string("gradey.guest.profile.message")
        }
        return hasFullName
            ? AppL10n.string("settings.profile.gradeyID")
            : AppL10n.string("settings.profile.addName.message")
    }

    var schoolAccounts: [LinkedAccount] {
        viewModel.accounts
            .filter(\.provider.isSchoolProvider)
            .sorted { lhs, rhs in
                if lhs.id == viewModel.activeSchoolAccountID {
                    return true
                }
                if rhs.id == viewModel.activeSchoolAccountID {
                    return false
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    var canteenAccounts: [LinkedAccount] {
        viewModel.accounts
            .filter { $0.provider == .stravaCZ }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var hasLocalSchoolSession: Bool {
        ((try? repository.bootstrapSession()) ?? nil) != nil
    }

    var hasLocalCanteenSession: Bool {
        ((try? stravaCZRepository.bootstrapSession()) ?? nil) != nil
    }

    var isSchoolCloudLinkMissing: Bool {
        !isGuestMode && account != nil && hasLocalSchoolSession && schoolAccounts.isEmpty
    }

    var isMealsCloudLinkMissing: Bool {
        !isGuestMode && account != nil && hasLocalCanteenSession && canteenAccounts.isEmpty
    }

    var notificationsAreAvailable: Bool {
        !isGuestMode && !schoolAccounts.isEmpty
    }

    var notificationControlsAreEnabled: Bool {
        notificationsAreAvailable && viewModel.notificationPreferences.newMarksEnabled
    }

    var quietHoursControlsAreEnabled: Bool {
        notificationControlsAreEnabled && viewModel.notificationPreferences.quietHoursEnabled
    }

    private var ageAttestationStatusMessage: LocalizedStringKey {
        switch AgeAttestationStore.shared.kind {
        case .sixteenOrOlder:
            "settings.privacy.age.sixteen"
        case .thirteenToFifteenWithParent, .underThirteen:
            "settings.privacy.age.teen"
        case nil:
            "settings.privacy.age.unknown"
        }
    }

    var notificationsUnavailableMessage: LocalizedStringKey? {
        if isGuestMode {
            return "settings.notifications.unavailable.guest"
        }
        if schoolAccounts.isEmpty {
            return "settings.notifications.unavailable.school"
        }
        return nil
    }

    var notificationPermissionLabel: String {
        switch notificationAuthorizationStatus {
        case .notDetermined:
            AppL10n.string("settings.notifications.permission.notDetermined")
        case .denied:
            AppL10n.string("settings.notifications.permission.denied")
        case .authorized:
            AppL10n.string("settings.notifications.permission.authorized")
        }
    }

    var notificationPermissionIconName: String {
        switch notificationAuthorizationStatus {
        case .notDetermined: "bell-dot"
        case .denied: "notification-off-01"
        case .authorized: "checkmark-circle-02"
        }
    }

    var notificationPermissionColor: Color {
        switch notificationAuthorizationStatus {
        case .notDetermined: .secondary
        case .denied: .gradelySystemOrange
        case .authorized: Brand.primary
        }
    }

    var notificationPermissionActionTitle: LocalizedStringKey {
        switch notificationAuthorizationStatus {
        case .notDetermined: "settings.notifications.permission.enable"
        case .denied: "settings.notifications.permission.openSettings"
        case .authorized: "settings.notifications.permission.authorized"
        }
    }

    var lockScreenDetailSummary: LocalizedStringKey {
        if !viewModel.notificationPreferences.newMarksEnabled {
            return "gradey.account.notifications.disabledSummary"
        }

        switch viewModel.notificationPreferences.lockScreenDetail {
        case .privateSummary:
            return "gradey.account.notifications.privateSummaryDetail"
        case .markAndSubject:
            return "gradey.account.notifications.markAndSubjectDetail"
        case .fullDetails:
            return "gradey.account.notifications.fullDetailsDetail"
        }
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? AppL10n.string("settings.about.unknown")
    }

    var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? AppL10n.string("settings.about.unknown")
    }

    var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil || actionErrorMessage != nil },
            set: {
                if !$0 {
                    viewModel.clearError()
                    actionErrorMessage = nil
                }
            }
        )
    }

    var unlinkDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingUnlinkAccount != nil },
            set: { if !$0 { pendingUnlinkAccount = nil } }
        )
    }

    var unlinkMessage: String {
        guard let pendingUnlinkAccount else {
            return AppL10n.string("gradey.account.unlink.messageFallback")
        }

        let key: String.LocalizationValue = pendingUnlinkAccount.provider.isSchoolProvider
            ? "settings.connected.unlink.school.message"
            : "settings.connected.unlink.canteen.message"
        return String(
            format: AppL10n.string(key),
            pendingUnlinkAccount.displayName
        )
    }

    var studentPicker: some View {
        NavigationStack {
            List(repository.availableStudents) { student in
                Button {
                    switchStudent(student)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(student.fullName)
                            .fixedSize(horizontal: false, vertical: true)
                        if let className = student.className {
                            Text(className)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(minHeight: 44, alignment: .leading)
                }
            }
            .navigationTitle("edupage.children.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") {
                        isStudentPickerPresented = false
                    }
                }
            }
        }
    }

    func formattedMinute(_ minute: Int) -> String {
        NotificationPreferences.date(forMinuteOfDay: minute)
            .formatted(date: .omitted, time: .shortened)
    }

    func quietTimeBinding(
        _ keyPath: WritableKeyPath<NotificationPreferences, Int>
    ) -> Binding<Date> {
        Binding(
            get: {
                NotificationPreferences.date(
                    forMinuteOfDay: viewModel.notificationPreferences[keyPath: keyPath],
                    in: .current
                )
            },
            set: { date in
                updateNotificationPreferences { preferences in
                    preferences[keyPath: keyPath] = NotificationPreferences.minuteOfDay(
                        from: date,
                        in: .current
                    )
                }
            }
        )
    }

    func updateNotificationPreferences(
        _ mutation: @escaping (inout NotificationPreferences) -> Void
    ) {
        var preferences = viewModel.notificationPreferences
        mutation(&preferences)
        preferences.quietHoursTimeZoneIdentifier = TimeZone.current.identifier
        Task {
            await viewModel.updateNotificationPreferences(preferences)
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        var preferences = viewModel.notificationPreferences

        if enabled {
            let currentStatus = await notificationAuthorizer.authorizationStatus()
            let resolvedStatus: NotificationAuthorizationStatus
            switch currentStatus {
            case .notDetermined:
                resolvedStatus = await notificationAuthorizer.requestAuthorization()
            case .denied:
                notificationAuthorizer.openSystemSettings()
                resolvedStatus = .denied
            case .authorized:
                resolvedStatus = await notificationAuthorizer.requestAuthorization()
            }

            notificationAuthorizationStatus = resolvedStatus
            guard resolvedStatus == .authorized else {
                preferences.newMarksEnabled = false
                await viewModel.updateNotificationPreferences(preferences)
                return
            }
        }

        preferences.newMarksEnabled = enabled
        preferences.quietHoursTimeZoneIdentifier = TimeZone.current.identifier
        await viewModel.updateNotificationPreferences(preferences)
    }

    func refreshNotificationAuthorization() async {
        notificationAuthorizationStatus = await notificationAuthorizer.authorizationStatus()
    }

    func resolveNotificationPermission() async {
        switch notificationAuthorizationStatus {
        case .notDetermined:
            notificationAuthorizationStatus = await notificationAuthorizer.requestAuthorization()
        case .denied:
            notificationAuthorizer.openSystemSettings()
        case .authorized:
            break
        }
    }

    func legalSettingsRow(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        iconName: String,
        url: URL,
        accessibilityIdentifier: String
    ) -> some View {
        Button {
            openURL(url)
        } label: {
            SettingsActionRow(
                title: title,
                message: message,
                iconName: iconName
            )
            .padding(20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(url.absoluteString)
        .accessibilityAddTraits(.isLink)
    }

    func openSchoolConnection(reconnectAccountID: String?) {
        #if os(macOS)
        detailPath.append(.schoolLink(reconnectAccountID: reconnectAccountID))
        #else
        if horizontalSizeClass == .regular {
            detailPath.append(.schoolLink(reconnectAccountID: reconnectAccountID))
        } else {
            compactPath.append(.schoolLink(reconnectAccountID: reconnectAccountID))
        }
        #endif
    }

    func openStravaConnection() {
        #if os(macOS)
        detailPath.append(.stravaCZLink)
        #else
        if horizontalSizeClass == .regular {
            detailPath.append(.stravaCZLink)
        } else {
            compactPath.append(.stravaCZLink)
        }
        #endif
    }

    func schoolConnectionView(reconnectAccountID: String?) -> some View {
        LoginView(
            repository: repository,
            schoolDirectoryProvider: schoolDirectoryProvider,
            presentationContext: reconnectAccountID == nil ? .linking : .reconnecting,
            prefill: schoolLoginPrefill(reconnectAccountID: reconnectAccountID)
        ) {
            completeSchoolConnection(reconnectAccountID: reconnectAccountID)
        }
    }

    var stravaConnectionView: some View {
        StravaCZConnectView(repository: stravaCZRepository) { session in
            let didLink = await viewModel.linkStravaCZ(session: session)
            if didLink {
                detailPath = []
                compactPath = []
            }
        }
    }

    func completeSchoolConnection(reconnectAccountID: String?) {
        Task {
            guard let session = try? await repository.validSession() else {
                return
            }
            let user = await repository.loadUser()
            let associatedAccount: LinkedAccount?
            if let reconnectAccountID,
               let linkedAccount = viewModel.accounts.first(where: { $0.id == reconnectAccountID }) {
                let didConnect = await viewModel.reconnect(
                    linkedAccount,
                    session: session,
                    user: user
                )
                associatedAccount = didConnect
                    ? viewModel.accounts.first(where: { $0.id == reconnectAccountID })
                    : nil
            } else {
                associatedAccount = await viewModel.linkSchool(session: session, user: user)
            }

            guard let associatedAccount else { return }
            try? repository.associateCurrentSession(with: associatedAccount)
            detailPath = []
            compactPath = []
            onSchoolLinked()
        }
    }

    func schoolLoginPrefill(reconnectAccountID: String?) -> SchoolLoginPrefill? {
        guard let reconnectAccountID,
              let account = viewModel.accounts.first(where: { $0.id == reconnectAccountID }),
              let session = try? repository.currentStoredSession()
        else {
            return nil
        }

        let schoolAccountCount = viewModel.accounts.filter(\.provider.isSchoolProvider).count
        return SchoolLoginPrefill(
            session: session,
            account: account,
            allowsUnscopedSession: schoolAccountCount == 1
        )
    }

    func activate(_ linkedAccount: LinkedAccount) {
        Task {
            guard let activation = await viewModel.activate(linkedAccount) else {
                return
            }

            do {
                _ = try await repository.activateLinkedSchoolAccount(activation)
                detailPath = []
                compactPath = []
                onSchoolLinked()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    func unlink(_ linkedAccount: LinkedAccount) {
        Task {
            await viewModel.unlink(linkedAccount)
            if linkedAccount.provider == .stravaCZ,
               viewModel.errorMessage == nil {
                await stravaCZRepository.logout()
            }
            pendingUnlinkAccount = nil
        }
    }

    func retrySchoolCloudLink() async {
        guard let session = try? repository.bootstrapSession() else { return }
        let user = await repository.loadUser()
        _ = await viewModel.linkSchool(session: session, user: user)
    }

    func retryMealsCloudLink() async {
        guard let session = try? stravaCZRepository.bootstrapSession() else { return }
        _ = await viewModel.linkStravaCZ(session: session)
    }

    func cloudLinkWarning(
        kind: OnboardingWarning.Kind,
        message: LocalizedStringKey,
        retry: @escaping () async -> Void
    ) -> some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SettingsHugeiconLabel(
                    "onboarding.sync.warning.title",
                    iconName: "alert-02",
                    iconColor: .gradelySystemOrange
                )
                    .font(.headline)
                    .foregroundStyle(Color.gradelySystemOrange)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task {
                        retryingCloudLink = kind
                        await retry()
                        retryingCloudLink = nil
                    }
                } label: {
                    if retryingCloudLink == kind {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    } else {
                        SettingsHugeiconLabel(
                            "onboarding.sync.warning.retry",
                            iconName: "refresh-04",
                            iconColor: Brand.primary
                        )
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                }
                .buttonStyle(.bordered)
                .tint(Brand.primary)
                .disabled(retryingCloudLink != nil)
                .accessibilityIdentifier("accountRetry-\(kind.rawValue)")
            }
        }
    }

    func switchStudent(_ student: SchoolStudentProfile) {
        Task {
            do {
                try await repository.switchEduPageStudent(student.id)
                isStudentPickerPresented = false
                NotificationCenter.default.post(
                    name: .gradelySchoolAccountDidChange,
                    object: nil
                )
            } catch {
                studentSwitchError = error.localizedDescription
            }
        }
    }

    func saveFullName() {
        Task {
            guard let updatedAccount = await viewModel.saveFullName() else { return }
            isFullNameFieldFocused = false
            onAccountUpdated(updatedAccount)
        }
    }

    func focusFullNameIfRequested() {
        guard shouldFocusFullName, !isGuestMode else { return }
        Task { @MainActor in
            await Task.yield()
            isFullNameFieldFocused = true
            shouldFocusFullName = false
        }
    }

    func exportGradeyData() {
        Task {
            isExporting = true
            exportedDataURL = await viewModel.exportData()
            isExporting = false
        }
    }

    func deleteGradeyAccount() {
        Task {
            isDeletingAccount = true
            let didDelete = await viewModel.deleteAccount()
            isDeletingAccount = false
            if didDelete {
                completeSignOut()
            }
        }
    }

    func completeSignOut() {
        dismiss()
        onSignedOut()
    }

    func unlockDebugModeIfNeeded() {
        if GradeyDebugModeStore().registerVersionTap(tapCount: &versionTapCount) {
            isDebugModeEnabled = true
        }
    }
}

// MARK: - Shared settings components

private extension View {
    @ViewBuilder
    func settingsRootNavigationChrome() -> some View {
        #if os(iOS)
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        #else
        self.navigationTitle("")
        #endif
    }
}

private struct SettingsScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark
            ? Color(.sRGB, red: 0.008, green: 0.045, blue: 0.046, opacity: 1)
            : Color.gradelyGroupedBackground)
            .overlay {
                if colorScheme == .light {
                    Brand.primary.opacity(0.018)
                }
            }
            .ignoresSafeArea()
    }
}

private struct SettingsSurfaceShape: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? Color(.sRGB, red: 0.045, green: 0.140, blue: 0.130, opacity: 1)
                    : Color.gradelySecondaryGroupedBackground
            )
            .overlay {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .fill(Brand.primary.opacity(0.035))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.025)
                            : Brand.primary.opacity(0.075),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.06 : 0.035),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

struct SettingsSurface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                SettingsSurfaceShape()
            }
    }
}

private struct SettingsCloseLabel: View {
    var body: some View {
        SettingsHugeIcon(
            iconName: "cancel-01",
            size: 15,
            color: .primary
        )
            .frame(width: 48, height: 48)
            .background(
                Brand.primary.opacity(0.10),
                in: Circle()
            )
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            }
            .contentShape(Circle())
    }
}

private struct SettingsOverviewGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        SettingsSurface(padding: 0) {
            VStack(spacing: 0) {
                content
            }
        }
    }
}

private struct SettingsOverviewRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let destination: SettingsDestination
    let subtitle: String
    let statusIconName: String?
    let statusColor: Color
    let statusAccessibilityLabel: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityLayout
                } else {
                    regularLayout
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.xl - 4, style: .continuous)
                        .fill(Brand.primary.opacity(0.10))
                        .padding(Spacing.xs)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var regularLayout: some View {
        HStack(spacing: Spacing.md) {
            SettingsIcon(iconName: destination.hugeiconName)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(destination.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let statusIconName, let statusAccessibilityLabel {
                    Label {
                        Text(statusAccessibilityLabel)
                    } icon: {
                        SettingsHugeIcon(
                            iconName: statusIconName,
                            size: 13,
                            color: statusColor
                        )
                    }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SettingsDisclosureIcon()
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.md) {
                SettingsIcon(iconName: destination.hugeiconName)

                Text(destination.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Spacing.sm)

                SettingsDisclosureIcon()
            }

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, SettingsIcon.frameSize + Spacing.md)

            if let statusIconName, let statusAccessibilityLabel {
                Label {
                    Text(statusAccessibilityLabel)
                } icon: {
                    SettingsHugeIcon(
                        iconName: statusIconName,
                        size: 13,
                        color: statusColor
                    )
                }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, SettingsIcon.frameSize + Spacing.md)
            }
        }
    }
}

private struct SettingsHugeIcon: View {
    let iconName: String
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        GradelyIcon(iconName, size: size)
            .foregroundStyle(color)
    }
}

private struct SettingsHugeiconLabel: View {
    let title: Text
    let iconName: String
    var iconColor: Color = .primary

    init(
        _ title: LocalizedStringKey,
        iconName: String,
        iconColor: Color = .primary
    ) {
        self.title = Text(title)
        self.iconName = iconName
        self.iconColor = iconColor
    }

    init(
        verbatim title: String,
        iconName: String,
        iconColor: Color = .primary
    ) {
        self.title = Text(verbatim: title)
        self.iconName = iconName
        self.iconColor = iconColor
    }

    var body: some View {
        Label {
            title
        } icon: {
            SettingsHugeIcon(
                iconName: iconName,
                size: 15,
                color: iconColor
            )
            .frame(width: 18, height: 18)
        }
    }
}

private struct SettingsIcon: View {
    static let frameSize: CGFloat = 32

    let iconName: String

    var body: some View {
        SettingsHugeIcon(
            iconName: iconName,
            size: 17,
            color: Brand.primary.opacity(0.88)
        )
        .frame(width: Self.frameSize, height: Self.frameSize)
    }
}

private struct SettingsDisclosureIcon: View {
    var body: some View {
        SettingsHugeIcon(
            iconName: "arrow-right-01",
            size: 14,
            color: Color.secondary.opacity(0.58)
        )
        .frame(width: 24, height: 24)
    }
}

private struct AccountAvatar: View {
    let name: String
    let avatarURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Brand.primary.opacity(0.38), lineWidth: 1)
        }
        .shadow(color: Brand.primary.opacity(0.22), radius: 12, x: 0, y: 6)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            Brand.gradient

            if initials.isEmpty {
                SettingsHugeIcon(
                    iconName: "user",
                    size: size * 0.36,
                    color: Brand.onAccent
                )
            } else {
                Text(initials)
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(Brand.onAccent)
    }

    private var initials: String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

private struct AdaptiveSettingsStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var content: Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.md) {
                content
            }
        } else {
            HStack(alignment: .center, spacing: Spacing.md) {
                content
            }
        }
    }
}

struct DetailSectionHeader: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.xs)
    }
}

private struct SettingsActionRow: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let iconName: String

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            SettingsIcon(iconName: iconName)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SettingsDisclosureIcon()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct EmptyServiceCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let iconName: String

    var body: some View {
        SettingsSurface {
            HStack(alignment: .top, spacing: Spacing.md) {
                SettingsIcon(iconName: iconName)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("linkedAccountsEmptyState")
    }
}

private struct SettingsAvailabilityMessage: View {
    let message: LocalizedStringKey

    init(_ message: LocalizedStringKey) {
        self.message = message
    }

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            SettingsHugeIcon(
                iconName: "information-circle",
                size: 14,
                color: .secondary
            )
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.gradelyTertiaryFill,
            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        )
    }
}

private struct SettingsMetadataRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Spacing.md)
                Text(value)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
            }
        }
        .font(.caption)
    }
}

struct SettingsValueRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                Text(title)
                Spacer(minLength: Spacing.md)
                Text(value)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                Text(value)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(minHeight: 44)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 20 + SettingsIcon.frameSize + Spacing.md)
    }
}
