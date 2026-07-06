import SwiftUI

struct GradeyAccountHubView: View {
    let account: GradeyAccount?
    let repository: SchoolRepository
    let stravaCZRepository: StravaCZRepository
    let schoolDirectoryProvider: any SchoolDirectoryProviding
    let onSchoolLinked: () -> Void
    let onSignedOut: () -> Void

    @State private var viewModel: GradeyAccountHubViewModel
    @State private var path: [LinkDestination] = []
    @State private var pendingUnlinkAccount: LinkedAccount?

    private enum LinkDestination: Hashable {
        case school
        case stravaCZ
    }

    init(
        account: GradeyAccount?,
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        linkedAccountRepository: LinkedAccountRepository,
        notificationClient: any DevicePushTokenClient,
        authClient: any GradeyAuthClient,
        preferencesStore: MarkNotificationSettingsStore,
        onSchoolLinked: @escaping () -> Void,
        onSignedOut: @escaping () -> Void
    ) {
        self.account = account
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.onSchoolLinked = onSchoolLinked
        self.onSignedOut = onSignedOut
        _viewModel = State(initialValue: GradeyAccountHubViewModel(
            linkedAccountRepository: linkedAccountRepository,
            notificationClient: notificationClient,
            authClient: authClient,
            preferencesStore: preferencesStore
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    quickActions
                    linkedAccounts
                    notificationSettings
                }
                .padding(Spacing.lg)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("accountHubScroll")
            .background(GradeyTwoPointZeroBackground())
            .navigationTitle("account.menu")
            .gradelyNavigationTitleDisplayMode(.inline)
            .navigationDestination(for: LinkDestination.self) { destination in
                switch destination {
                case .school:
                    LoginView(
                        repository: repository,
                        schoolDirectoryProvider: schoolDirectoryProvider,
                        presentationContext: .linking
                    ) {
                        completeSchoolLink()
                    }
                case .stravaCZ:
                    StravaCZConnectView(repository: stravaCZRepository) { session in
                        await viewModel.linkStravaCZ(session: session)
                        path = []
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .gradelyTopBarTrailing) {
                    Button(role: .destructive) {
                        onSignedOut()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .gradelyToolbarIconButton()
                    }
                    .accessibilityLabel(String(localized: "action.logout"))
                    .accessibilityIdentifier("accountSignOutButton")
                }
            }
        }
        .alert("gradey.account.title", isPresented: errorBinding) {
            Button("action.ok", role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "gradey.account.unlink.title",
            isPresented: unlinkDialogBinding,
            titleVisibility: .visible
        ) {
            if let account = pendingUnlinkAccount {
                Button("gradey.account.unlink.confirm", role: .destructive) {
                    Task {
                        await viewModel.unlink(account)
                        // Keep the Meals tab honest: dropping the linked account
                        // also signs the device out of that canteen session.
                        if account.provider == .stravaCZ, viewModel.errorMessage == nil {
                            await stravaCZRepository.logout()
                        }
                    }
                    pendingUnlinkAccount = nil
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
        .onAppear {
            viewModel.reload()
        }
    }

    /// Links the freshly authenticated school session, then pops back and
    /// notifies the app phase — in that order, so the hub row exists before
    /// `needsSchoolView` swaps to the TabView.
    private func completeSchoolLink() {
        Task {
            let session = try? await repository.validSession()
            let user = await repository.loadUser()
            if let session {
                await viewModel.linkSchool(session: session, user: user)
            }
            path = []
            onSchoolLinked()
        }
    }

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Brand.primary)
                        .frame(width: 54, height: 54)
                        .background(Brand.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(account?.displayName ?? String(localized: "gradey.auth.title"))
                            .font(.title2.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                        Text(account?.email ?? String(localized: "gradey.account.appleConnected"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("gradey.account.header.subtitle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Spacing.xs)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: Spacing.md) {
                    StatPill(title: String(localized: "gradey.account.stat.linked"), value: "\(viewModel.accounts.count)", systemImage: "link")
                    StatPill(
                        title: String(localized: "gradey.account.stat.alerts"),
                        value: viewModel.notificationPreferences.newMarksEnabled
                            ? String(localized: "gradey.account.alerts.on")
                            : String(localized: "gradey.account.alerts.off"),
                        systemImage: "bell.fill"
                    )
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("gradey.account.connect.title")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.md) {
                    linkSchoolButton
                    linkStravaCZButton
                }

                VStack(spacing: Spacing.md) {
                    linkSchoolButton
                    linkStravaCZButton
                }
            }
        }
    }

    private var linkSchoolButton: some View {
        Button {
            path.append(.school)
        } label: {
            AccountActionLabel(
                title: "gradey.account.linkSchool.title",
                subtitle: "gradey.account.linkSchool.short",
                systemImage: "building.columns.fill"
            )
        }
        .buttonStyle(AccountActionButtonStyle())
        .accessibilityIdentifier("accountLinkSchoolButton")
    }

    private var linkStravaCZButton: some View {
        Button {
            path.append(.stravaCZ)
        } label: {
            AccountActionLabel(
                title: "gradey.account.linkStrava.title",
                subtitle: "gradey.account.linkStrava.short",
                systemImage: "fork.knife"
            )
        }
        .buttonStyle(AccountActionButtonStyle())
        .accessibilityIdentifier("accountLinkStravaCZButton")
    }

    private var linkedAccounts: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("gradey.account.linked.title")

            if viewModel.accounts.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Label("gradey.account.empty.title", systemImage: "link.badge.plus")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("gradey.account.empty.message")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            path.append(.school)
                        } label: {
                            Label("gradey.account.linkSchool.title", systemImage: "building.columns.fill")
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("accountEmptyLinkSchoolButton")
                        }
                        .buttonStyle(AccountActionButtonStyle())
                        .accessibilityIdentifier("accountEmptyLinkSchoolButton")
                    }
                }
                .accessibilityIdentifier("linkedAccountsEmptyState")
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(viewModel.accounts) { account in
                        LinkedAccountRow(account: account) {
                            pendingUnlinkAccount = account
                        }
                    }
                }
            }
        }
    }

    private var notificationSettings: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label("gradey.account.notifications.title", systemImage: "bell.badge.fill")
                        .font(.headline)
                    Text("gradey.account.notifications.message")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(isOn: Binding(
                    get: { viewModel.notificationPreferences.newMarksEnabled },
                    set: { newValue in
                        var preferences = viewModel.notificationPreferences
                        preferences.newMarksEnabled = newValue
                        Task { await viewModel.updateNotificationPreferences(preferences) }
                    }
                )) {
                    Text("gradey.account.notifications.toggle")
                }
                .tint(Brand.primary)
                .accessibilityIdentifier("newMarkNotificationsToggle")

                Picker("gradey.account.notifications.lockScreen", selection: Binding(
                    get: { viewModel.notificationPreferences.lockScreenDetail },
                    set: { detail in
                        var preferences = viewModel.notificationPreferences
                        preferences.lockScreenDetail = detail
                        Task { await viewModel.updateNotificationPreferences(preferences) }
                    }
                )) {
                    Text("gradey.account.notifications.privateSummary").tag(NotificationLockScreenDetail.privateSummary)
                    Text("gradey.account.notifications.markAndSubject").tag(NotificationLockScreenDetail.markAndSubject)
                    Text("gradey.account.notifications.fullDetails").tag(NotificationLockScreenDetail.fullDetails)
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.notificationPreferences.newMarksEnabled)
                .opacity(viewModel.notificationPreferences.newMarksEnabled ? 1 : 0.48)
                .accessibilityIdentifier("lockScreenDetailPicker")

                Text(lockScreenDetailSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lockScreenDetailSummary")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }

    private var unlinkDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingUnlinkAccount != nil },
            set: { if !$0 { pendingUnlinkAccount = nil } }
        )
    }

    private var unlinkMessage: String {
        guard let pendingUnlinkAccount else {
            return String(localized: "gradey.account.unlink.messageFallback")
        }
        return String(
            format: String(localized: "gradey.account.unlink.message"),
            pendingUnlinkAccount.displayName
        )
    }

    private var lockScreenDetailSummary: LocalizedStringKey {
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
}

private struct StatPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(Brand.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.headline.weight(.bold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

private struct AccountActionLabel: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .frame(width: 34, height: 34)
                .background(Brand.onAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(Brand.onAccent.opacity(0.78))
            }

            Spacer(minLength: Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LinkedAccountRow: View {
    let account: LinkedAccount
    let onUnlink: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(Brand.primary)
                .frame(width: 42, height: 42)
                .background(Brand.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(account.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("linkedAccountRow-\(account.id)")
                Text(account.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            StatusChip(text: account.status.displayName, color: account.status == .active ? Brand.primary : .gradelySystemOrange)

            Menu {
                Button(role: .destructive, action: onUnlink) {
                    Label("gradey.account.unlink.action", systemImage: "trash")
                }
                .accessibilityIdentifier("linkedAccountUnlinkAction-\(account.id)")
            } label: {
                Label {
                    Text("gradey.account.moreActions")
                } icon: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("linkedAccountUnlinkMenu-\(account.id)")
            }
            .accessibilityLabel(String(localized: "gradey.account.moreActions"))
            .accessibilityIdentifier("linkedAccountUnlinkMenu-\(account.id)")
        }
        .padding(Spacing.md)
        .background(Color.gradelySecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var icon: String {
        switch account.provider {
        case .bakalari, .eduPage: "building.columns.fill"
        case .stravaCZ: "fork.knife"
        }
    }
}

private struct AccountActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Brand.onAccent)
            .padding(Spacing.md)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
