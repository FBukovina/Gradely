import SwiftUI

struct OnboardingConnectionMigrationResult: Equatable, Sendable {
    let school: OnboardingCloudLinkStatus
    let meals: OnboardingCloudLinkStatus
}

@MainActor
protocol OnboardingLocalConnectionMigrating {
    func migrateLocalConnections() async -> OnboardingConnectionMigrationResult
}

@MainActor
struct DefaultOnboardingLocalConnectionMigrator: OnboardingLocalConnectionMigrating {
    let repository: SchoolRepository
    let stravaCZRepository: StravaCZRepository
    let linkedAccountRepository: LinkedAccountRepository

    func migrateLocalConnections() async -> OnboardingConnectionMigrationResult {
        let existingAccounts = linkedAccountRepository.loadAccounts()
        let hasLinkedSchool = existingAccounts.contains { $0.provider.isSchoolProvider }
        let hasLinkedMeals = existingAccounts.contains { $0.provider == .stravaCZ }

        let schoolStatus: OnboardingCloudLinkStatus
        if hasLinkedSchool {
            schoolStatus = .linked
        } else if let session = try? repository.bootstrapSession() {
            let user = await repository.loadUser()
            do {
                _ = try await linkedAccountRepository.linkCurrentSchoolAccount(
                    session: session,
                    user: user
                )
                schoolStatus = .linked
            } catch {
                schoolStatus = .failed(message: error.localizedDescription)
            }
        } else {
            schoolStatus = .notAttempted
        }

        let mealsStatus: OnboardingCloudLinkStatus
        if hasLinkedMeals {
            mealsStatus = .linked
        } else if let session = try? stravaCZRepository.bootstrapSession() {
            do {
                _ = try await linkedAccountRepository.linkCurrentStravaCZAccount(session: session)
                mealsStatus = .linked
            } catch {
                mealsStatus = .failed(message: error.localizedDescription)
            }
        } else {
            mealsStatus = .notAttempted
        }

        return OnboardingConnectionMigrationResult(
            school: schoolStatus,
            meals: mealsStatus
        )
    }
}

struct OnboardingView: View {
    let journey: OnboardingJourney
    let appViewModel: AppViewModel
    let repository: SchoolRepository
    let stravaCZRepository: StravaCZRepository
    let schoolDirectoryProvider: any SchoolDirectoryProviding
    let gradeyAuthClient: any GradeyAuthClient
    let linkedAccountRepository: LinkedAccountRepository
    let devicePushTokenClient: any DevicePushTokenClient
    let notificationSettingsStore: MarkNotificationSettingsStore
    let notificationAuthorizer: any NotificationAuthorizing
    let onFinished: () -> Void
    private let localConnectionMigrator: any OnboardingLocalConnectionMigrating

    @State private var viewModel: OnboardingViewModel
    @State private var supportViewModel: SupportTipViewModel
    @State private var isWorking = false
    @State private var schoolLabel: String?
    @State private var didAttemptUpgradeMigration = false
    @AccessibilityFocusState private var focusedStep: OnboardingStep?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var languageStore = AppLanguageStore.shared

    init(
        journey: OnboardingJourney,
        appViewModel: AppViewModel,
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        gradeyAuthClient: any GradeyAuthClient,
        linkedAccountRepository: LinkedAccountRepository,
        devicePushTokenClient: any DevicePushTokenClient,
        notificationSettingsStore: MarkNotificationSettingsStore,
        notificationAuthorizer: any NotificationAuthorizing,
        supportTipProvider: any SupportTipProviding,
        progressStore: any OnboardingProgressStoring = OnboardingProgressStore(),
        localConnectionMigrator: (any OnboardingLocalConnectionMigrating)? = nil,
        onFinished: @escaping () -> Void
    ) {
        self.journey = journey
        self.appViewModel = appViewModel
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.gradeyAuthClient = gradeyAuthClient
        self.linkedAccountRepository = linkedAccountRepository
        self.devicePushTokenClient = devicePushTokenClient
        self.notificationSettingsStore = notificationSettingsStore
        self.notificationAuthorizer = notificationAuthorizer
        self.localConnectionMigrator = localConnectionMigrator
            ?? DefaultOnboardingLocalConnectionMigrator(
                repository: repository,
                stravaCZRepository: stravaCZRepository,
                linkedAccountRepository: linkedAccountRepository
            )
        self.onFinished = onFinished
        _viewModel = State(initialValue: OnboardingViewModel(
            journey: journey,
            progressStore: progressStore
        ))
        _supportViewModel = State(initialValue: SupportTipViewModel(
            supportTipProvider: supportTipProvider,
            isSignedIn: appViewModel.gradeyAccount != nil
        ))
    }

    var body: some View {
        ZStack {
            stepContent
                .id(viewModel.currentStep)
                .transition(stepTransition)

            if isWorking {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()

                ProgressView()
                    .controlSize(.large)
                    .tint(Brand.primary)
                    .padding(Spacing.xl)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityLabel(AppL10n.string("onboarding.sync.warning.retrying"))
                    .accessibilityIdentifier("onboardingWorking")
            }
        }
        .environment(\.locale, languageStore.locale)
        .safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.currentStep != .welcome, viewModel.currentStep != .school {
                progressHeader
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: viewModel.currentStep)
        .onChange(of: viewModel.currentStep) { _, newStep in
            focusedStep = newStep
        }
        .onChange(of: appViewModel.phase) {
            Task {
                await reconcileWithPersistedState()
                await migrateUpgradeConnectionsIfNeeded()
            }
        }
        .task {
            await reconcileWithPersistedState()
            await migrateUpgradeConnectionsIfNeeded()
            focusedStep = viewModel.currentStep
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            welcomeStep
        case .account:
            accountStep
        case .school:
            schoolStep
        case .notifications:
            notificationsStep
        case .ready:
            readyStep
        case .support:
            supportStep
        }
    }

    private var progressHeader: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                if viewModel.canGoBack {
                    Button {
                        viewModel.goBack()
                    } label: {
                        GradelyLabel("onboarding.back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.primary)
                    .accessibilityIdentifier("onboardingBackButton")
                }

                Spacer(minLength: Spacing.sm)

                Text(progressText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboardingProgressLabel")
            }

            ProgressView(value: viewModel.progressFraction)
                .tint(Brand.primary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Spacing.md)
        .background(Color.gradelyGroupedBackground.opacity(0.96))
        .accessibilityElement(children: .contain)
    }

    private var welcomeStep: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        GradelyIcon(systemName: "graduationcap.fill", size: 36)
                            .foregroundStyle(Brand.onAccent)
                            .frame(width: 88, height: 88)
                            .background(
                                Brand.gradient,
                                in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            )
                            .shadow(color: Brand.primary.opacity(0.28), radius: 16, x: 0, y: 8)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("onboarding.welcome.title")
                                .font(.gradelyDisplay())
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($focusedStep, equals: .welcome)

                            Text("onboarding.welcome.body")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(spacing: Spacing.md) {
                        OnboardingLandingBenefit(
                            systemImage: "sun.max.fill",
                            title: "onboarding.welcome.benefit.today.title",
                            message: "onboarding.welcome.benefit.today.body"
                        )
                        OnboardingLandingBenefit(
                            systemImage: "chart.line.uptrend.xyaxis",
                            title: "onboarding.welcome.benefit.insights.title",
                            message: "onboarding.welcome.benefit.insights.body"
                        )
                        OnboardingLandingBenefit(
                            systemImage: "sparkles",
                            title: "onboarding.welcome.benefit.extras.title",
                            message: "onboarding.welcome.benefit.extras.body"
                        )
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("settings.language.title")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        AppLanguageOptionsList(
                            store: languageStore,
                            usesSettingsChrome: false,
                            compact: true
                        )
                    }

                    VStack(spacing: Spacing.md) {
                        primaryButton("onboarding.getStarted", systemImage: "arrow.right") {
                            viewModel.chooseGetStarted()
                        }
                        .accessibilityIdentifier("onboardingPrimaryButton")

                        Button {
                            viewModel.chooseLogIn()
                        } label: {
                            Text("onboarding.logIn")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 50)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Brand.primary)
                        .background(
                            Color.gradelyTertiaryFill,
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        )
                        .accessibilityIdentifier("onboardingLoginButton")
                    }
                    .padding(.top, Spacing.xs)
                }
                .padding(.horizontal, 20)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityIdentifier("onboardingStep-welcome")
    }

    private var accountStep: some View {
        OnboardingAccountStep(
            journey: journey,
            accountIntent: viewModel.accountIntent,
            authClient: gradeyAuthClient,
            onContinueWithoutAccount: {
                Task { await chooseGuestMode() }
            },
            onSignedIn: {
                Task { await completeGradeyIDSignIn() }
            }
        )
        .accessibilityIdentifier("onboardingStep-account")
    }

    private var schoolStep: some View {
        LoginView(
            repository: repository,
            schoolDirectoryProvider: schoolDirectoryProvider,
            presentationContext: .linking,
            onBackFromSchool: {
                viewModel.goBack()
            }
        ) {
            Task { await completeSchoolConnection() }
        }
    }

    private var notificationsStep: some View {
        brandedScreen(
            step: .notifications,
            icon: "bell.badge.fill",
            title: "onboarding.notifications.title",
            message: "onboarding.notifications.body"
        ) {
            SettingsModalSurface {
                GradelyLabel("gradey.account.notifications.message", systemImage: "checkmark.shield.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            primaryButton("onboarding.notifications.enable", systemImage: "bell.fill") {
                Task { await enableNotifications() }
            }
            .accessibilityIdentifier("onboardingNotificationsEnableButton")

            secondaryButton("onboarding.notifications.notNow") {
                Task { await skipNotifications() }
            }
            .accessibilityIdentifier("onboardingNotificationsNotNowButton")
        }
    }

    private var readyStep: some View {
        brandedScreen(
            step: .ready,
            icon: "checkmark.seal.fill",
            title: "onboarding.ready.title",
            message: "onboarding.ready.body"
        ) {
            SettingsModalSurface {
                VStack(spacing: 0) {
                    OnboardingSummaryRow(
                        title: "onboarding.ready.school",
                        value: schoolLabel ?? AppL10n.string("onboarding.ready.connected"),
                        systemImage: "building.columns.fill"
                    )
                    Divider().padding(.leading, 44)
                    OnboardingSummaryRow(
                        title: "onboarding.ready.account",
                        value: accountSummary,
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    Divider().padding(.leading, 44)
                    OnboardingSummaryRow(
                        title: "onboarding.ready.notifications",
                        value: notificationSummary,
                        systemImage: "bell.fill"
                    )
                }
            }

            ForEach(viewModel.warnings) { warning in
                warningCard(warning)
            }

            if viewModel.notificationStatus == .denied {
                secondaryButton("gradey.account.notifications.title") {
                    notificationAuthorizer.openSystemSettings()
                }
                .accessibilityIdentifier("onboardingOpenNotificationSettingsButton")
            }

            primaryButton("onboarding.ready.open", systemImage: "arrow.right.circle.fill") {
                if viewModel.finish() {
                    onFinished()
                }
            }
            .disabled(!viewModel.canFinish)
            .accessibilityIdentifier("onboardingFinishButton")
        }
    }

    private var supportStep: some View {
        brandedScreen(
            step: .support,
            icon: "heart.fill",
            title: "onboarding.upgrade.support.title",
            message: "onboarding.upgrade.support.body"
        ) {
            ForEach(viewModel.warnings) { warning in
                warningCard(warning)
            }

            SupportTipOptionsContent(viewModel: supportViewModel)
                .accessibilityIdentifier("onboardingSupportOptions")
                .onAppear {
                    supportViewModel.isSignedIn = appViewModel.gradeyAccount != nil
                }

            primaryButton("onboarding.upgrade.support.continue", systemImage: "arrow.right.circle.fill") {
                if viewModel.finish() {
                    onFinished()
                }
            }
            .disabled(!viewModel.canFinish)
            .accessibilityIdentifier("onboardingUpgradeFinishButton")
        }
    }

    private func brandedScreen<Content: View>(
        step: OnboardingStep,
        icon: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            SettingsModalBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    OnboardingStepHero(icon: icon, title: title, message: message)
                        .accessibilityFocused($focusedStep, equals: step)

                    content()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.xxl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityIdentifier("onboardingStep-\(step.rawValue)")
    }

    private func primaryButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Text(title)
                GradelyIcon(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    private func secondaryButton(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Brand.primary)
        .background(Color.gradelyTertiaryFill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func warningCard(_ warning: OnboardingWarning) -> some View {
        SettingsModalSurface {
            VStack(alignment: .leading, spacing: Spacing.md) {
                GradelyLabel("onboarding.sync.warning.title", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.gradelySystemOrange)

                Text(warningMessageKey(for: warning.kind))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = warning.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button {
                    Task {
                        switch warning.kind {
                        case .schoolCloudLink:
                            await retrySchoolCloudLink()
                        case .mealsCloudLink:
                            await retryMealsCloudLink()
                        case .notificationPreferences:
                            await retryNotificationPreference()
                        }
                    }
                } label: {
                    GradelyLabel("onboarding.sync.warning.retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Brand.primary)
                .disabled(isWorking)
                .accessibilityIdentifier("onboardingRetry-\(warning.kind.rawValue)")
            }
        }
    }

    private var progressText: String {
        String(
            format: AppL10n.string("onboarding.progress"),
            Int64(viewModel.progressPosition),
            Int64(viewModel.progressCount)
        )
    }

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var accountSummary: String {
        switch viewModel.accountMode {
        case .gradeyID:
            return AppL10n.string("onboarding.ready.gradeyID")
        case .guest, .undecided:
            return AppL10n.string("onboarding.ready.localOnly")
        }
    }

    private var notificationSummary: String {
        switch viewModel.notificationStatus {
        case .enabled:
            return AppL10n.string("onboarding.notifications.enabled")
        case .unavailable:
            return viewModel.accountMode == .guest
                ? AppL10n.string("onboarding.notifications.unavailable")
                : AppL10n.string("onboarding.notifications.disabled")
        case .notDetermined, .notNow, .denied:
            return AppL10n.string("onboarding.notifications.disabled")
        }
    }

    private func chooseGuestMode() async {
        isWorking = true
        await appViewModel.continueWithoutAccount()
        viewModel.chooseGuest()
        isWorking = false
        await reconcileWithPersistedState()
    }

    private func completeGradeyIDSignIn() async {
        isWorking = true
        await appViewModel.markGradeySignedIn()
        isWorking = false
        await reconcileWithPersistedState()
        if appViewModel.phase == .signedIn, viewModel.completeRestoredSession() {
            onFinished()
            return
        }

        viewModel.markSignedIn()
        await migrateUpgradeConnectionsIfNeeded()
    }

    private func completeSchoolConnection() async {
        isWorking = true
        appViewModel.markSignedIn()

        let storedSession = try? repository.bootstrapSession()
        schoolLabel = storedSession.flatMap(schoolDisplayName)
        let cloudStatus: OnboardingCloudLinkStatus
        let resolvedSession: StoredSession?
        if let storedSession {
            resolvedSession = storedSession
        } else {
            resolvedSession = try? await repository.validSession()
        }

        if viewModel.accountMode == .gradeyID,
           let session = resolvedSession {
            let user = await repository.loadUser()
            do {
                let account = try await linkedAccountRepository.linkCurrentSchoolAccount(session: session, user: user)
                try? repository.associateCurrentSession(with: account)
                cloudStatus = .linked
            } catch {
                cloudStatus = .failed(message: error.localizedDescription)
            }
        } else {
            cloudStatus = .notApplicable
        }

        viewModel.markSchoolConnected(cloudLink: cloudStatus)
        isWorking = false
    }

    private func enableNotifications() async {
        isWorking = true
        let status = await notificationAuthorizer.requestAuthorization()
        let isEnabled = status == .authorized
        await persistNotificationPreference(isEnabled)
        viewModel.markNotification(isEnabled ? .enabled : .denied)
        isWorking = false
    }

    private func skipNotifications() async {
        isWorking = true
        await persistNotificationPreference(false)
        viewModel.skipNotifications()
        isWorking = false
    }

    private func retrySchoolCloudLink() async {
        guard viewModel.accountMode == .gradeyID else { return }
        let storedSession = try? repository.bootstrapSession()
        let resolvedSession: StoredSession?
        if let storedSession {
            resolvedSession = storedSession
        } else {
            resolvedSession = try? await repository.validSession()
        }
        guard let session = resolvedSession else { return }

        isWorking = true
        let user = await repository.loadUser()
        do {
            let account = try await linkedAccountRepository.linkCurrentSchoolAccount(session: session, user: user)
            try? repository.associateCurrentSession(with: account)
            viewModel.recordSchoolCloudLinkRetry(.linked)
            _ = viewModel.openNotificationsAfterSchoolLinkRetry()
        } catch {
            viewModel.recordSchoolCloudLinkRetry(.failed(message: error.localizedDescription))
        }
        isWorking = false
    }

    private func retryMealsCloudLink() async {
        guard viewModel.accountMode == .gradeyID,
              let session = try? stravaCZRepository.bootstrapSession()
        else {
            return
        }

        isWorking = true
        do {
            _ = try await linkedAccountRepository.linkCurrentStravaCZAccount(session: session)
            viewModel.recordMealsCloudLinkRetry(.linked)
        } catch {
            viewModel.recordMealsCloudLinkRetry(.failed(message: error.localizedDescription))
        }
        isWorking = false
    }

    private func persistNotificationPreference(_ enabled: Bool) async {
        var preferences = notificationSettingsStore.preferences
        preferences.newMarksEnabled = enabled
        preferences = preferences.preparedForServerUpdate()
        notificationSettingsStore.preferences = preferences

        do {
            let session = try await gradeyAuthClient.validSession()
            let canonicalPreferences = try await devicePushTokenClient.updateNotificationPreferences(
                preferences,
                gradeySession: session
            )
            notificationSettingsStore.preferences = canonicalPreferences
            viewModel.clearNotificationSyncFailure()
        } catch {
            viewModel.recordNotificationSyncFailure(error.localizedDescription)
        }
    }

    private func retryNotificationPreference() async {
        isWorking = true
        await persistNotificationPreference(
            notificationSettingsStore.preferences.newMarksEnabled
        )
        isWorking = false
    }

    private func migrateUpgradeConnectionsIfNeeded() async {
        guard journey == .upgrade,
              !didAttemptUpgradeMigration,
              viewModel.accountMode == .gradeyID
        else {
            return
        }

        didAttemptUpgradeMigration = true
        let shouldManageOverlay = !isWorking
        if shouldManageOverlay {
            isWorking = true
        }
        let result = await localConnectionMigrator.migrateLocalConnections()
        viewModel.recordUpgradeMigration(school: result.school, meals: result.meals)
        if shouldManageOverlay {
            isWorking = false
        }
        await reconcileWithPersistedState()
    }

    private func reconcileWithPersistedState() async {
        guard !isWorking, appViewModel.phase != .checking else { return }

        let accounts = linkedAccountRepository.loadAccounts()
        let schoolCloudLinked = accounts.contains { $0.provider == .bakalari || $0.provider == .eduPage }
        let mealsCloudLinked = accounts.contains { $0.provider == .stravaCZ }
        let schoolSession = try? repository.bootstrapSession()
        let mealsSession = try? stravaCZRepository.bootstrapSession()
        let authorization = await notificationAuthorizer.authorizationStatus()

        if let schoolSession {
            schoolLabel = schoolDisplayName(schoolSession)
        }
        let accountMode: OnboardingAccountMode
        if appViewModel.isGuestMode {
            accountMode = .guest
        } else if appViewModel.gradeyAccount != nil {
            accountMode = .gradeyID
        } else {
            accountMode = .undecided
        }

        let notificationStatus: OnboardingNotificationStatus
        if accountMode != .gradeyID || !schoolCloudLinked {
            notificationStatus = .unavailable
        } else if authorization == .authorized, notificationSettingsStore.preferences.newMarksEnabled {
            notificationStatus = .enabled
        } else if authorization == .denied {
            notificationStatus = .denied
        } else if !notificationSettingsStore.preferences.newMarksEnabled {
            notificationStatus = .notNow
        } else {
            notificationStatus = .notDetermined
        }

        viewModel.reconcile(with: OnboardingSnapshot(
            accountMode: accountMode,
            hasSchoolConnection: schoolSession != nil,
            isSchoolCloudLinked: schoolCloudLinked,
            notificationStatus: notificationStatus,
            hasMealsConnection: mealsSession != nil,
            isMealsCloudLinked: mealsCloudLinked
        ))
    }

    private func schoolDisplayName(_ session: StoredSession) -> String {
        session.linkedAccountSchoolName
            ?? session.linkedAccountDisplayName
            ?? session.provider.displayName
    }

    private func warningMessageKey(for kind: OnboardingWarning.Kind) -> LocalizedStringKey {
        switch kind {
        case .schoolCloudLink:
            return "onboarding.sync.warning.school"
        case .mealsCloudLink:
            return "onboarding.sync.warning.meals"
        case .notificationPreferences:
            return "onboarding.sync.warning.notifications"
        }
    }
}

private struct OnboardingLandingBenefit: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            GradelyIcon(systemName: systemImage)
                .foregroundStyle(Brand.primary)
                .frame(width: 36, height: 36)
                .background(
                    Brand.primary.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingSummaryRow: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            SettingsModalSystemIcon(systemName: systemImage)
                .accessibilityHidden(true)

            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.sm)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Guided onboarding") {
    let environment = AppEnvironment(
        repository: SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache()
        ),
        schoolDirectoryProvider: MockSchoolDirectoryProvider(refreshResult: PreviewData.schoolDirectorySchools),
        requiresGradeyID: true
    )
    let appViewModel = AppViewModel(
        repository: environment.repository,
        stravaCZRepository: environment.stravaCZRepository,
        gradeyAuthClient: environment.gradeyAuthClient,
        linkedAccountRepository: environment.linkedAccountRepository,
        guestModeStore: environment.guestModeStore,
        requiresGradeyID: true
    )

    OnboardingView(
        journey: .newUser,
        appViewModel: appViewModel,
        repository: environment.repository,
        stravaCZRepository: environment.stravaCZRepository,
        schoolDirectoryProvider: environment.schoolDirectoryProvider,
        gradeyAuthClient: environment.gradeyAuthClient,
        linkedAccountRepository: environment.linkedAccountRepository,
        devicePushTokenClient: environment.devicePushTokenClient,
        notificationSettingsStore: environment.notificationSettingsStore,
        notificationAuthorizer: MockNotificationAuthorizer(),
        supportTipProvider: environment.supportTipProvider,
        progressStore: InMemoryOnboardingProgressStore()
    ) {}
}
