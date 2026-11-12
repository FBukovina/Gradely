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
    case vavruskaLink
}

private enum SettingsConnectionRoute: Hashable {
    case schoolLink(reconnectAccountID: String?)
    case stravaCZLink
    case vavruskaLink
}

private extension SettingsRoute {
    init(_ route: SettingsConnectionRoute) {
        switch route {
        case .schoolLink(let reconnectAccountID): self = .schoolLink(reconnectAccountID: reconnectAccountID)
        case .stravaCZLink: self = .stravaCZLink
        case .vavruskaLink: self = .vavruskaLink
        }
    }

    var connectionRoute: SettingsConnectionRoute? {
        switch self {
        case .detail: nil
        case .schoolLink(let reconnectAccountID): .schoolLink(reconnectAccountID: reconnectAccountID)
        case .stravaCZLink: .stravaCZLink
        case .vavruskaLink: .vavruskaLink
        }
    }
}

struct GradeyAccountHubView: View {
    let account: GradeyAccount?
    let isGuestMode: Bool
    let repository: SchoolRepository
    let stravaCZRepository: StravaCZRepository
    let vavruska: VavruskaViewModel?
    let friends: FriendsViewModel?
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
    /// Lets the debug panel open any recap, out yet or not.
    let recapStore: RecapStore?

    @AppStorage(PlannerNotificationScheduler.enabledKey) private var plannerRemindersEnabled = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("settings.showMealsTab") private var showMealsTab = true
    @Bindable private var languageStore = AppLanguageStore.shared
    @AppStorage(GradeyDebugModeStore.storageKey) private var isDebugModeEnabled = false

    @State private var viewModel: GradeyAccountHubViewModel
    @State private var detailPath: [SettingsConnectionRoute] = []
    @State private var selectedDestination: SettingsDestination?
    /// Whether you opened `selectedDestination` yourself; the wide layout
    /// preselects Account, which shouldn't open it when the screen narrows.
    @State private var isShowingDestination = false
    @State private var pendingUnlinkAccount: LinkedAccount?
    @State private var isVavruskaDisconnectPresented = false
    @State private var isSupportSheetPresented = false
    @State private var isCreditsPresented = false
    @State private var isPrivacyChangesPresented = false
    @State private var isStudentPickerPresented = false
    @State private var studentSwitchError: String?
    @State private var retryingCloudLink: OnboardingWarning.Kind?
    @State private var notificationAuthorizationStatus: NotificationAuthorizationStatus = .notDetermined
    @State private var isRequestingPlannerPermission = false
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
        vavruska: VavruskaViewModel? = nil,
        friends: FriendsViewModel? = nil,
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
        onDebugResetAsNewUser: @escaping () -> Void = {},
        recapStore: RecapStore? = nil
    ) {
        self.account = account
        self.isGuestMode = isGuestMode
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.vavruska = vavruska
        self.friends = friends
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
        self.recapStore = recapStore
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
            .confirmationDialog(
                "settings.connected.dance.disconnect.title",
                isPresented: $isVavruskaDisconnectPresented,
                titleVisibility: .visible
            ) {
                Button("settings.connected.dance.disconnect.confirm", role: .destructive) {
                    Task { await vavruska?.disconnect() }
                }
                .accessibilityIdentifier("vavruskaDisconnectConfirmButton")
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text("settings.connected.dance.disconnect.message")
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
            .sheet(isPresented: $isPrivacyChangesPresented) {
                PrivacyPolicyUpdateView(mode: .review)
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
                vavruska?.reloadFromStorage()
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
        macLayout
            .frame(minWidth: 720, idealWidth: 820, minHeight: 480, idealHeight: 600)
        #else
        if horizontalSizeClass == .regular {
            splitLayout
        } else {
            compactLayout
        }
        #endif
    }

    /// The single-column stack, read from the same state as the split layout
    /// so the open page survives folding, unfolding and rotation.
    private var compactPath: [SettingsRoute] {
        get {
            let page = isShowingDestination ? selectedDestination.map { [SettingsRoute.detail($0)] } : nil
            return (page ?? []) + detailPath.map(SettingsRoute.init)
        }
        nonmutating set {
            if case .detail(let destination) = newValue.first {
                selectedDestination = destination
                isShowingDestination = true
            } else {
                isShowingDestination = false
            }
            detailPath = newValue.compactMap(\.connectionRoute)
        }
    }

    private var compactLayout: some View {
        NavigationStack(path: Binding(get: { compactPath }, set: { compactPath = $0 })) {
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
                    isShowingDestination = true
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
                    noDestinationSelected
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var noDestinationSelected: some View {
        ContentUnavailableView {
            Label {
                Text("settings.detail.select.title")
            } icon: {
                GradelyIcon("gears", size: 28)
                    .foregroundStyle(.secondary)
            }
        } description: {
            Text("settings.detail.select.message")
        }
        .gradelyScreenBackground()
    }

    #if os(macOS)
    /// The Mac Settings window: a native source-list sidebar like System
    /// Settings, with the selected page in the detail column.
    private var macLayout: some View {
        NavigationSplitView {
            List(selection: macSelection) {
                Section {
                    macSidebarAccountRow
                        .tag(SettingsDestination.account)
                }
                Section {
                    macSidebarRow(.connectedServices)
                    macSidebarRow(.notifications)
                    macSidebarRow(.privacyData)
                }
                Section("settings.group.app") {
                    macSidebarRow(.appPreferences)
                    macSidebarRow(.supportAbout)
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 300)
            .toolbar(removing: .sidebarToggle)
            .accessibilityIdentifier("accountHubScroll")
        } detail: {
            NavigationStack(path: $detailPath) {
                if let selectedDestination {
                    detailPage(selectedDestination)
                        .navigationTitle(selectedDestination.title)
                        .navigationDestination(for: SettingsConnectionRoute.self) { route in
                            splitConnectionRoute(route)
                        }
                } else {
                    noDestinationSelected
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
    }

    private var macSelection: Binding<SettingsDestination?> {
        Binding(
            get: { selectedDestination },
            set: { destination in
                guard let destination else { return }
                select(destination) {
                    selectedDestination = destination
                    detailPath = []
                }
            }
        )
    }

    private var macSidebarAccountRow: some View {
        HStack(spacing: Spacing.sm) {
            AccountAvatar(name: profileAvatarName, avatarURL: viewModel.account?.avatarURL, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(profileDisplayName)
                    .font(.gradely(.body).weight(.semibold))
                    .lineLimit(1)
                Text(profileSubtitle)
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settingsDestination-account")
    }

    private func macSidebarRow(_ destination: SettingsDestination) -> some View {
        let status = overviewStatus(for: destination)
        return Label {
            HStack {
                Text(destination.title)
                Spacer(minLength: 0)
                if let status {
                    GradelyIcon(status.iconName, size: 13)
                        .foregroundStyle(status.color)
                        .accessibilityLabel(status.accessibilityLabel)
                }
            }
        } icon: {
            GradelyIcon(destination.hugeiconName, size: 15)
                .foregroundStyle(Brand.primary)
        }
        .tag(destination)
        .accessibilityIdentifier("settingsDestination-\(destination.rawValue)")
    }
    #endif

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
                            GradelyIcon("arrow-left-01", size: 18)
                                .foregroundStyle(.primary)
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
        case .vavruskaLink:
            vavruskaConnectionView
        }
    }

    @ViewBuilder
    private func splitConnectionRoute(_ route: SettingsConnectionRoute) -> some View {
        switch route {
        case .schoolLink(let reconnectAccountID):
            schoolConnectionView(reconnectAccountID: reconnectAccountID)
        case .stravaCZLink:
            stravaConnectionView
        case .vavruskaLink:
            vavruskaConnectionView
        }
    }

    private func overview(
        selectedDestination: SettingsDestination?,
        onSelect: @escaping (SettingsDestination) -> Void
    ) -> some View {
        ZStack {
            SettingsBackground()

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
                GradelyModalCloseLabel(size: 48)
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
        SettingsSurface(padding: 0) {
            Button(action: onSelect) {
                AdaptiveSettingsStack {
                    AccountAvatar(
                        name: profileAvatarName,
                        avatarURL: viewModel.account?.avatarURL,
                        size: 44
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profileDisplayName)
                            .font(.gradely(.headline))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(profileSubtitle)
                            .font(.gradely(.footnote))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SettingsDisclosureIcon()
                }
                .settingsRowInsets(vertical: Spacing.md)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Brand.primary.opacity(0.10))
                            .padding(Spacing.xs)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    /// Only pages with a state to report get a second line.
    private func overviewSubtitle(for destination: SettingsDestination) -> String? {
        switch destination {
        case .account, .privacyData, .supportAbout:
            return nil
        case .connectedServices:
            // A service that's waiting for the user is named in the status
            // line instead, so it isn't said twice.
            var parts: [String] = []
            if schoolAccounts.isEmpty {
                parts.append(AppL10n.string("settings.overview.school.notConnected"))
            } else if !schoolAccounts.contains(where: accountNeedsAttention) {
                parts.append(AppL10n.string("settings.overview.school.active"))
            }

            if canteenAccounts.isEmpty {
                parts.append(AppL10n.string("settings.overview.canteen.notConnected"))
            } else if !canteenAccounts.contains(where: accountNeedsAttention) {
                parts.append(AppL10n.string("settings.overview.canteen.connected"))
            }

            if let vavruska, let course = vavruska.course, vavruska.phase != .needsReconnect {
                parts.append(course.courseCode.map { String(format: AppL10n.string("settings.overview.dance.connected"), $0) }
                    ?? AppL10n.string("settings.connected.dance.title"))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
        case .appPreferences:
            return languageStore.selection.displayName
        }
    }

    private func overviewStatus(
        for destination: SettingsDestination
    ) -> (iconName: String, color: Color, accessibilityLabel: String)? {
        switch destination {
        case .connectedServices:
            let services = servicesNeedingAttention
            guard let first = services.first else { return nil }
            // "Školní účty, jídelna: Vyžaduje akci"
            let names = ([first] + services.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
            return (
                "alert-circle",
                .gradelySystemOrange,
                "\(names): \(AppL10n.string("gradey.account.status.actionRequired"))"
            )
        default:
            return nil
        }
    }

    /// Titles of the connected services that are waiting for the user.
    private var servicesNeedingAttention: [String] {
        var titles: [String] = []
        if schoolAccounts.contains(where: accountNeedsAttention) {
            titles.append(AppL10n.string("settings.connected.school.title"))
        }
        if canteenAccounts.contains(where: accountNeedsAttention) {
            titles.append(AppL10n.string("settings.connected.canteen.title"))
        }
        if let vavruska, vavruska.course != nil, vavruska.phase == .needsReconnect {
            titles.append(AppL10n.string("settings.connected.dance.title"))
        }
        return titles
    }

    private func accountNeedsAttention(_ account: LinkedAccount) -> Bool {
        account.status == .actionRequired || account.status == .failed
    }
}

// MARK: - Detail destinations

private extension GradeyAccountHubView {
    func detailPage(_ destination: SettingsDestination) -> some View {
        ZStack {
            SettingsBackground()

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
            if isGuestMode {
                DetailSectionHeader(title: "gradey.guest.accountSection.title")

                SettingsSurface {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SettingsHugeiconLabel(
                            "gradey.guest.accountSection.heading",
                            iconName: "user-add-02"
                        )
                            .font(.gradely(.headline))

                        Button {
                            dismiss()
                            onLeaveGuestMode()
                        } label: {
                            SettingsHugeiconLabel(
                                "gradey.guest.accountSection.action",
                                iconName: "user-check-02",
                                iconColor: Brand.primary
                            )
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Brand.primary)
                        .accessibilityIdentifier("leaveGuestModeButton")
                    }
                }
            } else {
                DetailSectionHeader(title: "settings.account.profile.title")

                SettingsSurface {
                    accountNameEditor
                }
                .onAppear {
                    focusFullNameIfRequested()
                }
                .onChange(of: shouldFocusFullName) { _, shouldFocus in
                    guard shouldFocus else { return }
                    focusFullNameIfRequested()
                }
            }

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    if repository.availableStudents.count > 1 {
                        Button {
                            isStudentPickerPresented = true
                        } label: {
                            SettingsActionRow(title: "edupage.children.switch", iconName: "students")
                                .settingsRowInsets()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("switchEduPageStudentButton")

                        SettingsRowDivider()
                    }

                    Button {
                        isSignOutConfirmationPresented = true
                    } label: {
                        SettingsActionRow(
                            title: accountSignOutTitle,
                            iconName: "logout-01",
                            tint: .red,
                            accessory: .none
                        )
                        .settingsRowInsets()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("accountSignOutButton")

                    if !isGuestMode {
                        SettingsRowDivider()

                        deleteGradeyAccountRow
                    }
                }
            }
        }
    }

    /// The name field with its error, the Apple ID under it. Save shows up
    /// once there's a change to save.
    var accountNameEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("settings.account.name.title")
                    .font(.gradely(.subheadline).weight(.semibold))
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
                .gradelyBorderlessTextFields()
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: ControlMetrics.fieldHeight)
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
                    .font(.gradely(.caption))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("accountFullNameValidationError")
                } else if let fullNameErrorMessage = viewModel.fullNameErrorMessage {
                    SettingsHugeiconLabel(
                        verbatim: fullNameErrorMessage,
                        iconName: "alert-circle",
                        iconColor: .red
                    )
                    .font(.gradely(.caption))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("accountFullNameSaveError")
                }

                if viewModel.canSaveFullName || viewModel.isUpdatingFullName {
                    Button {
                        saveFullName()
                    } label: {
                        if viewModel.isUpdatingFullName {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: ControlMetrics.minHeight)
                        } else {
                            Text("settings.account.name.save")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: ControlMetrics.minHeight)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.primary)
                    .disabled(!viewModel.canSaveFullName)
                    .accessibilityIdentifier("accountFullNameSaveButton")
                }
            }

            Divider()

            SettingsValueRow(
                title: "settings.account.appleID.title",
                value: viewModel.account?.email
                    ?? AppL10n.string("gradey.account.appleConnected")
            )
            .accessibilityIdentifier("accountAppleIDValue")
        }
    }

    var connectedServicesDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(title: "settings.connected.school.title")

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    if isSchoolCloudLinkMissing {
                        cloudLinkWarning(
                            kind: .schoolCloudLink,
                            message: "onboarding.sync.warning.school"
                        ) {
                            await retrySchoolCloudLink()
                        }
                        SettingsRowDivider()
                    }

                    ForEach(schoolAccounts) { linkedAccount in
                        connectedAccountRow(linkedAccount)
                        SettingsRowDivider()
                    }

                    connectServiceRow(
                        title: schoolAccounts.isEmpty
                            ? "gradey.account.linkSchool.title"
                            : "settings.connected.school.addAnother",
                        iconName: schoolAccounts.isEmpty ? "school" : "add-01",
                        accessibilityIdentifier: "accountLinkSchoolButton"
                    ) {
                        openSchoolConnection(reconnectAccountID: nil)
                    }
                    .disabled(isGuestMode)
                }
            }

            DetailSectionHeader(title: "settings.connected.canteen.title")

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    if isMealsCloudLinkMissing {
                        cloudLinkWarning(
                            kind: .mealsCloudLink,
                            message: "onboarding.sync.warning.meals"
                        ) {
                            await retryMealsCloudLink()
                        }
                        SettingsRowDivider()
                    }

                    if canteenAccounts.isEmpty {
                        connectServiceRow(
                            title: "gradey.account.linkStrava.title",
                            iconName: "restaurant-02",
                            accessibilityIdentifier: "accountLinkStravaCZButton"
                        ) {
                            openStravaConnection()
                        }
                        .disabled(isGuestMode)
                    } else {
                        ForEach(Array(canteenAccounts.enumerated()), id: \.element.id) { index, linkedAccount in
                            if index > 0 {
                                SettingsRowDivider()
                            }
                            connectedAccountRow(linkedAccount)
                        }
                    }
                }
            }

            // Always listed next to school and canteen: this is where people look for it.
            if let vavruska {
                DetailSectionHeader(title: "settings.connected.dance.title")
                vavruskaSection(vavruska)
            }

            if let friends {
                DetailSectionHeader(title: "friends.settings.title")
                FriendsSettingsSection(friends: friends)
            }

            if isGuestMode {
                SettingsAvailabilityMessage("settings.connected.guest.explanation")
            }
        }
    }

    /// A row that starts connecting a service.
    func connectServiceRow(
        title: LocalizedStringKey,
        iconName: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SettingsActionRow(title: title, iconName: iconName)
                .settingsRowInsets()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    /// A linked school or canteen account: who it is, what it needs, when it
    /// last synced. Its actions are in the menu.
    func connectedAccountRow(_ linkedAccount: LinkedAccount) -> some View {
        let isSchool = linkedAccount.provider.isSchoolProvider
        let isInUse = isSchool && viewModel.activeSchoolAccountID == linkedAccount.id

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                SettingsIcon(name: isSchool ? "school" : "restaurant-02")

                VStack(alignment: .leading, spacing: 2) {
                    Text(linkedAccount.displayName)
                        .font(.gradely(.body).weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("linkedAccountRow-\(linkedAccount.id)")

                    Text(linkedAccount.subtitle)
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    if isSchool, !isInUse {
                        Button {
                            activate(linkedAccount)
                        } label: {
                            GradelyLabel("settings.connected.activate", systemImage: "checkmark")
                        }
                        .accessibilityIdentifier("linkedAccountActivate-\(linkedAccount.id)")
                    }

                    Button(role: .destructive) {
                        pendingUnlinkAccount = linkedAccount
                    } label: {
                        GradelyLabel("gradey.account.unlink.action", systemImage: "trash")
                    }
                    .accessibilityIdentifier("linkedAccountUnlinkAction-\(linkedAccount.id)")
                } label: {
                    SettingsRowMenuLabel()
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel(AppL10n.string("settings.connected.actions"))
                .accessibilityIdentifier("linkedAccountMenu-\(linkedAccount.id)")
            }

            Group {
                if linkedAccount.status != .active {
                    SettingsRowStatusLabel(
                        text: linkedAccount.actionRequiredReason.flatMap { $0.isEmpty ? nil : $0 }
                            ?? linkedAccount.status.displayName,
                        iconName: "alert-02",
                        color: .gradelySystemOrange
                    )
                } else if isInUse, schoolAccounts.count > 1 {
                    SettingsRowStatusLabel(
                        text: AppL10n.string("settings.connected.inUse"),
                        iconName: "tick-02",
                        color: Brand.primary
                    )
                }

                if isSchool, accountNeedsAttention(linkedAccount) {
                    Button {
                        openSchoolConnection(reconnectAccountID: linkedAccount.id)
                    } label: {
                        SettingsInlineLink(title: "settings.connected.reconnect")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("linkedAccountReconnect-\(linkedAccount.id)")
                }

                if let summary = syncSummary(
                    lastSyncedAt: linkedAccount.lastSyncedAt,
                    lastPolledAt: linkedAccount.lastPolledAt
                ) {
                    Text(verbatim: summary)
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isSchool {
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
                        Text("settings.connected.accountNotifications.title")
                            .font(.gradely(.subheadline))
                    }
                    .tint(Brand.primary)
                    .disabled(
                        isGuestMode
                            || viewModel.isMutating(linkedAccount)
                            || !viewModel.notificationPreferences.newMarksEnabled
                    )
                    .accessibilityIdentifier("linkedAccountNotificationsToggle-\(linkedAccount.id)")
                }
            }
            .padding(.leading, SettingsIcon.frameSize + Spacing.md)
        }
        .settingsRowInsets(vertical: Spacing.md)
        .disabled(viewModel.isMutating(linkedAccount))
        .overlay {
            if viewModel.isMutating(linkedAccount) {
                ProgressView()
            }
        }
    }

    /// "Last sync · 9. 11. 14:02", or the last check when it never synced.
    func syncSummary(lastSyncedAt: Date?, lastPolledAt: Date? = nil) -> String? {
        if let lastSyncedAt {
            return "\(AppL10n.string("settings.connected.lastSync")) · \(shortTimestamp(lastSyncedAt))"
        }
        if let lastPolledAt {
            return "\(AppL10n.string("settings.connected.lastChecked")) · \(shortTimestamp(lastPolledAt))"
        }
        return nil
    }

    func shortTimestamp(_ date: Date) -> String {
        "\(SchoolDateFormatting.shortDate(date)) \(date.formatted(date: .omitted, time: .shortened))"
    }

    var notificationsDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(title: "settings.notifications.device.title")

            SettingsSurface(padding: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    AdaptiveSettingsStack {
                        SettingsIcon(name: notificationPermissionIconName)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.notifications.permission.title")
                                .font(.gradely(.body).weight(.medium))
                            Text(notificationPermissionLabel)
                                .font(.gradely(.caption))
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
                            .frame(minHeight: ControlMetrics.minHeight)
                            .accessibilityIdentifier("notificationPermissionAction")
                        }
                    }

                    Divider()

                    Toggle(isOn: Binding(get: { plannerRemindersEnabled }, set: { enabled in
                        if !enabled { plannerRemindersEnabled = false }
                        else { Task { await enablePlannerReminders() } }
                    })) { Text("planner.reminders.toggle") }
                        .tint(Brand.primary)
                        .disabled(isRequestingPlannerPermission)
                        .accessibilityIdentifier("plannerRemindersToggle")
                }
            }

            DetailSectionHeader(title: "gradey.account.notifications.title")

            SettingsSurface(padding: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.md) {
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

                    // A menu picker on its own shows only the value: say what it sets.
                    AdaptiveSettingsStack {
                        Text("gradey.account.notifications.lockScreen")
                            .frame(maxWidth: .infinity, alignment: .leading)

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
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .disabled(!notificationControlsAreEnabled)
                        .accessibilityIdentifier("lockScreenDetailPicker")
                    }
                }
            }

            DetailSectionHeader(title: "settings.notifications.quietHours.title")

            SettingsSurface(padding: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.md) {
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
            SettingsSurface(padding: Spacing.md) { GradeySiriDiscoverySettingsView() }
            DetailSectionHeader(title: "settings.privacy.documents.title")

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    legalSettingsRow(
                        title: "legal.privacyPolicy",
                        iconName: "security-lock",
                        url: AppLinks.privacyPolicyURL,
                        accessibilityIdentifier: "privacyPolicyLink"
                    )

                    SettingsRowDivider()

                    legalSettingsRow(
                        title: "legal.termsOfUse",
                        iconName: "left-to-right-list-bullet",
                        url: AppLinks.termsOfUseURL,
                        accessibilityIdentifier: "termsOfUseLink"
                    )

                    SettingsRowDivider()

                    Button {
                        isPrivacyChangesPresented = true
                    } label: {
                        SettingsActionRow(
                            title: "privacy.update.settingsRow.title",
                            iconName: "legal-document-01"
                        )
                        .settingsRowInsets()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacyChangesLink")
                }
            }

            DetailSectionHeader(title: "settings.privacy.age.title")

            SettingsAvailabilityMessage(ageAttestationStatusMessage)
                .accessibilityIdentifier("settingsPrivacyAgeStatus")

            #if os(iOS)
            SettingsAvailabilityMessage("settings.privacy.intercom.note")
                .accessibilityIdentifier("settingsPrivacyIntercomNote")
            #endif

            DetailSectionHeader(title: "settings.privacy.export.title")

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    Button {
                        exportGradeyData()
                    } label: {
                        SettingsActionRow(
                            title: "settings.privacy.export.prepare",
                            iconName: "file-export",
                            accessory: isExporting || viewModel.isExporting ? .progress : .none
                        )
                        .settingsRowInsets()
                    }
                    .buttonStyle(.plain)
                    .disabled(isGuestMode || isExporting || viewModel.isExporting)
                    .accessibilityIdentifier("accountExportButton")

                    if let exportedDataURL {
                        SettingsRowDivider()

                        ShareLink(item: exportedDataURL) {
                            SettingsActionRow(
                                title: "settings.privacy.export.share",
                                iconName: "share-03",
                                accessory: .none
                            )
                            .settingsRowInsets()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("accountExportShareButton")
                    }
                }
            }

            if isGuestMode {
                SettingsAvailabilityMessage("settings.privacy.guest.explanation")
            }
        }
    }

    var appPreferencesDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            AppLanguageOptionsList(store: languageStore, usesSettingsChrome: true)

            SettingsSurface(padding: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Toggle(isOn: $showMealsTab) {
                        Text("settings.showMealsTab")
                    }
                    .tint(Brand.primary)
                    .accessibilityIdentifier("showMealsTabToggle")

                    if let vavruska {
                        Divider()

                        Toggle(isOn: Binding(
                            get: { vavruska.isEnabled },
                            set: { vavruska.isEnabled = $0 }
                        )) {
                            Text("settings.showVavruska")
                        }
                        .tint(Brand.primary)
                        .accessibilityIdentifier("showVavruskaToggle")

                        if vavruska.isEnabled, vavruska.course == nil {
                            Button {
                                openVavruskaConnection()
                            } label: {
                                SettingsInlineLink(title: "settings.connected.dance.connect")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("preferencesConnectVavruskaButton")
                        }
                    }
                }
            }
        }
    }

    var supportAboutDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            DetailSectionHeader(title: "settings.support.title")

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    #if os(iOS)
                    Button(action: IntercomIdentity.presentMessenger) {
                        SettingsActionRow(
                            title: "settings.support.chat",
                            iconName: "message-multiple-01"
                        )
                        .settingsRowInsets()
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
                            iconName: "favourite"
                        )
                        .settingsRowInsets()
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
                        .settingsRowInsets()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("developerContactLink")

                    SettingsRowDivider()

                    Link(destination: AppLinks.githubRepositoryURL) {
                        SettingsActionRow(
                            title: "github.repository",
                            iconName: "github-01"
                        )
                        .settingsRowInsets()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("githubRepositoryLink")
                }
            }

            DetailSectionHeader(title: "settings.about.title")

            SettingsSurface(padding: 0) {
                VStack(spacing: 0) {
                    Button {
                        isCreditsPresented = true
                    } label: {
                        SettingsActionRow(
                            title: "credits.title",
                            iconName: "user-group"
                        )
                        .settingsRowInsets()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsCreditsButton")

                    SettingsRowDivider(leadingInset: SettingsRowMetrics.inset)

                    Button {
                        unlockDebugModeIfNeeded()
                    } label: {
                        SettingsValueRow(
                            title: "settings.about.version",
                            value: "\(appVersion) (\(appBuild))"
                        )
                        .settingsRowInsets(vertical: Spacing.md)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settingsVersionRow")
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
                    },
                    recapStore: recapStore
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

    var deleteGradeyAccountRow: some View {
        Button {
            isDeleteConfirmationPresented = true
        } label: {
            SettingsActionRow(
                title: "settings.privacy.delete.action",
                iconName: "delete-02",
                tint: .red,
                accessory: isDeletingAccount || viewModel.isDeletingAccount ? .progress : .none
            )
            .settingsRowInsets()
        }
        .buttonStyle(.plain)
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
        (notificationsAreAvailable && viewModel.notificationPreferences.newMarksEnabled) || plannerRemindersEnabled
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
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(repository.availableStudents) { student in
                        Divider()

                        Button {
                            switchStudent(student)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(student.fullName)
                                    .font(.gradely(.body).weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let className = student.className {
                                    Text(className)
                                        .font(.gradely(.caption))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: ControlMetrics.minHeight, alignment: .leading)
                            .padding(.vertical, Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.lg)
            }
            .gradelyScreenBackground()
            .navigationTitle("edupage.children.title")
            .gradelyNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") {
                        isStudentPickerPresented = false
                    }
                }
            }
        }
        .gradelyMacSheetSize(minWidth: 420, idealWidth: 480, minHeight: 360, idealHeight: 460)
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
            await viewModel.updateNotificationPreferences(preferences, locallyOnly: isGuestMode)
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

    func enablePlannerReminders() async {
        guard !isRequestingPlannerPermission else { return }
        isRequestingPlannerPermission = true
        defer { isRequestingPlannerPermission = false }
        let current = await notificationAuthorizer.authorizationStatus()
        if current == .denied {
            notificationAuthorizationStatus = .denied
            notificationAuthorizer.openSystemSettings()
            return
        }
        let resolved = current == .authorized ? current : await notificationAuthorizer.requestAuthorization()
        notificationAuthorizationStatus = resolved
        plannerRemindersEnabled = resolved == .authorized
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
        iconName: String,
        url: URL,
        accessibilityIdentifier: String
    ) -> some View {
        Button {
            openURL(url)
        } label: {
            SettingsActionRow(title: title, iconName: iconName)
                .settingsRowInsets()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(url.absoluteString)
        .accessibilityAddTraits(.isLink)
    }

    func openSchoolConnection(reconnectAccountID: String?) {
        // The single-column stack shows `detailPath` too.
        detailPath.append(.schoolLink(reconnectAccountID: reconnectAccountID))
    }

    func openVavruskaConnection() {
        detailPath.append(.vavruskaLink)
    }

    @ViewBuilder
    var vavruskaConnectionView: some View {
        if let vavruska {
            VavruskaConnectView(viewModel: vavruska) {
                detailPath = []
                compactPath = []
            }
        }
    }

    /// The dance course: which one, whether it needs a new sign-in, when it
    /// last synced. Unlinking is in the menu.
    func vavruskaSection(_ vavruska: VavruskaViewModel) -> some View {
        SettingsSurface(padding: 0) {
            if let course = vavruska.course {
                let ended = vavruska.isCourseEnded(at: Date())
                let needsReconnect = vavruska.phase == .needsReconnect

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.md) {
                        SettingsIcon(name: "music-note-03")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: course.courseCode.map { String(format: AppL10n.string("vavruska.course.title"), $0) }
                                ?? AppL10n.string("vavruska.title"))
                                .font(.gradely(.body).weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("vavruskaCourseRow")
                            Text(verbatim: [AppL10n.string("settings.connected.dance.school"), course.scheduleSummary]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.gradely(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Menu {
                            Button(role: .destructive) {
                                isVavruskaDisconnectPresented = true
                            } label: {
                                GradelyLabel("gradey.account.unlink.action", systemImage: "trash")
                            }
                            .accessibilityIdentifier("vavruskaDisconnectButton")
                        } label: {
                            SettingsRowMenuLabel()
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppL10n.string("settings.connected.actions"))
                        .accessibilityIdentifier("vavruskaMenu")
                    }

                    Group {
                        if needsReconnect {
                            SettingsRowStatusLabel(
                                text: AppL10n.string("settings.connected.dance.status.reconnect"),
                                iconName: "alert-02",
                                color: .gradelySystemOrange
                            )
                        } else if ended {
                            SettingsRowStatusLabel(
                                text: AppL10n.string("settings.connected.dance.status.ended"),
                                iconName: "calendar-03",
                                color: .secondary
                            )
                        }

                        if needsReconnect || ended {
                            Button {
                                openVavruskaConnection()
                            } label: {
                                SettingsInlineLink(title: ended ? "vavruska.ended.button" : "settings.connected.reconnect")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("vavruskaReconnectSettingsButton")
                        }

                        if let summary = syncSummary(lastSyncedAt: vavruska.snapshot.lastFetchedAt) {
                            Text(verbatim: summary)
                                .font(.gradely(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Toggle(isOn: Binding(
                            get: { vavruska.ticketAlertsEnabled },
                            set: { enabled in Task { await vavruska.setTicketAlertsEnabled(enabled) } }
                        )) {
                            Text("vavruska.alerts.toggle")
                                .font(.gradely(.subheadline))
                        }
                        .tint(Brand.primary)
                        .accessibilityIdentifier("settingsVavruskaTicketAlertsToggle")
                    }
                    .padding(.leading, SettingsIcon.frameSize + Spacing.md)
                }
                .settingsRowInsets(vertical: Spacing.md)
            } else {
                connectServiceRow(
                    title: "settings.connected.dance.connect",
                    iconName: "music-note-03",
                    accessibilityIdentifier: "accountLinkVavruskaButton"
                ) {
                    openVavruskaConnection()
                }
            }
        }
    }

    func openStravaConnection() {
        detailPath.append(.stravaCZLink)
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
            } catch SchoolAuthenticationError.deviceSignInRequired {
                openSchoolConnection(reconnectAccountID: linkedAccount.id)
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
        // The first row of its service's list: what's wrong, and the one
        // thing to do about it.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.md) {
                SettingsIcon(name: "alert-02", color: .gradelySystemOrange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.gradely(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    retryingCloudLink = kind
                    await retry()
                    retryingCloudLink = nil
                }
            } label: {
                if retryingCloudLink == kind {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minHeight: ControlMetrics.minHeight)
                } else {
                    SettingsInlineLink(title: "onboarding.sync.warning.retry")
                }
            }
            .buttonStyle(.plain)
            .disabled(retryingCloudLink != nil)
            .padding(.leading, SettingsIcon.frameSize + Spacing.md)
            .accessibilityIdentifier("accountRetry-\(kind.rawValue)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsRowMetrics.inset)
        // The link is as tall as a control, so it brings its own space below.
        .padding(.top, Spacing.md)
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
    /// The page's live state, for pages that have one worth showing here.
    let subtitle: String?
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
            .settingsRowInsets()
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
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
            SettingsIcon(name: destination.hugeiconName)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.title)
                    .font(.gradely(.body).weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // What needs the user comes before what's fine.
                if let statusIconName, let statusAccessibilityLabel {
                    Label {
                        Text(statusAccessibilityLabel)
                    } icon: {
                        GradelyIcon(statusIconName, size: 13)
                            .foregroundStyle(statusColor)
                    }
                        .font(.gradely(.caption).weight(.semibold))
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
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
                SettingsIcon(name: destination.hugeiconName)

                Text(destination.title)
                    .font(.gradely(.body).weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Spacing.sm)

                SettingsDisclosureIcon()
            }

            if let statusIconName, let statusAccessibilityLabel {
                Label {
                    Text(statusAccessibilityLabel)
                } icon: {
                    GradelyIcon(statusIconName, size: 13)
                        .foregroundStyle(statusColor)
                }
                    .font(.gradely(.caption).weight(.semibold))
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, SettingsIcon.frameSize + Spacing.md)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.gradely(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, SettingsIcon.frameSize + Spacing.md)
            }
        }
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
            GradelyIcon(iconName, size: 15)
                .foregroundStyle(iconColor)
                .frame(width: 18, height: 18)
        }
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
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            Brand.primary.opacity(0.14)

            if initials.isEmpty {
                GradelyIcon("user", size: size * 0.42)
            } else {
                Text(initials)
                    .font(.gradely(size: size * 0.36, weight: .bold))
            }
        }
        .foregroundStyle(Brand.primary)
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

    var body: some View {
        Text(title)
            .font(.gradely(.headline))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, Spacing.xs)
    }
}

/// One tappable Settings row: icon, title, an optional value underneath and
/// what sits at the trailing edge. `tint` colours the icon and title, for
/// sign out and delete.
struct SettingsActionRow: View {
    enum Accessory {
        case disclosure
        case progress
        case none
    }

    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    let iconName: String
    var tint: Color?
    var accessory: Accessory = .disclosure

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            SettingsIcon(name: iconName, color: tint ?? Brand.primary.opacity(0.88))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.gradely(.body).weight(.medium))
                    .foregroundStyle(tint ?? Color.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Text(message)
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switch accessory {
            case .disclosure:
                SettingsDisclosureIcon()
            case .progress:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            case .none:
                EmptyView()
            }
        }
        .frame(minHeight: ControlMetrics.minHeight)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Insets of a row inside `SettingsSurface(padding: 0)`.
    func settingsRowInsets(vertical: CGFloat = Spacing.sm) -> some View {
        padding(.horizontal, SettingsRowMetrics.inset)
            .padding(.vertical, vertical)
    }
}

/// The "…" that opens a row's menu.
struct SettingsRowMenuLabel: View {
    var body: some View {
        GradelyIcon(systemName: "ellipsis.circle")
            .foregroundStyle(.secondary)
            .frame(width: SettingsIcon.frameSize, height: SettingsIcon.frameSize)
            .contentShape(Rectangle())
    }
}

/// One line of state under a connected service's name.
private struct SettingsRowStatusLabel: View {
    let text: String
    let iconName: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            GradelyIcon(iconName, size: 13)
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.gradely(.caption).weight(.semibold))
        .foregroundStyle(color)
    }
}

/// A green text link that starts at the row's text edge.
private struct SettingsInlineLink: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
            GradelyIcon("arrow-right-01", size: 13)
        }
        .font(.gradely(.subheadline).weight(.semibold))
        .foregroundStyle(Brand.primary)
        .frame(minHeight: ControlMetrics.minHeight, alignment: .leading)
        .contentShape(Rectangle())
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
            GradelyIcon("information-circle", size: 14)
                .foregroundStyle(.secondary)
        }
        .font(.gradely(.footnote))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
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
        .frame(minHeight: ControlMetrics.minHeight)
    }
}
