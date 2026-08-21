import Foundation
import Testing
@testable import Gradely

struct GradeyPlatformTests {
    @Test func markFingerprintUsesProviderIDWhenAvailable() {
        let subject = testSubject(id: "subj-tv", abbrev: "TVY")
        let mark = testMark(id: "mark-123", subjectID: "subj-tv", markText: "1")

        let fingerprint = MarkFingerprintBuilder.fingerprint(
            for: mark,
            subject: subject,
            provider: .bakalari,
            linkedAccountID: "account-1"
        )

        #expect(fingerprint.source == .providerID)
        #expect(fingerprint.providerMarkID == "mark-123")
        #expect(fingerprint.value == "bakalari:account-1:subj-tv:provider:mark-123")
    }

    @Test func markFingerprintFallsBackToStableContentHashWithoutProviderID() {
        let subject = testSubject(id: "subj-tv", abbrev: "TVY")
        let first = testMark(id: "", subjectID: "subj-tv", markText: "1")
        let second = testMark(id: "", subjectID: "subj-tv", markText: "1")

        let firstFingerprint = MarkFingerprintBuilder.fingerprint(
            for: first,
            subject: subject,
            provider: .bakalari,
            linkedAccountID: "account-1"
        )
        let secondFingerprint = MarkFingerprintBuilder.fingerprint(
            for: second,
            subject: subject,
            provider: .bakalari,
            linkedAccountID: "account-1"
        )

        #expect(firstFingerprint.source == .contentHash)
        #expect(firstFingerprint.providerMarkID == nil)
        #expect(firstFingerprint.value == secondFingerprint.value)
    }

    @Test func schoolProviderSecretPayloadNeverIncludesPasswords() throws {
        let eduPageData = EduPageSessionData(
            sessionID: "session",
            username: "student",
            password: "super-secret-password",
            gsecHash: "hash",
            userID: "user",
            schoolName: "School",
            activeStudent: nil,
            linkedStudents: [],
            subjects: []
        )
        let session = StoredSession(
            accessToken: "session",
            refreshToken: "",
            tokenType: "Cookie",
            expiresAt: .distantFuture,
            baseURL: URL(string: "https://school.edupage.org")!,
            provider: .eduPage,
            eduPage: eduPageData
        )

        let payload = ProviderSecretSanitizer.schoolPayload(from: session)
        let data = try JSONEncoder.sessionEncoder.encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""

        #expect(!json.contains("super-secret-password"))
        #expect(json.contains("session"))
        #expect(json.contains("hash"))
        #expect(!json.contains("bakalari"))
    }

    @Test func schoolProviderSecretPayloadIncludesBakalariCredentialsForPolling() throws {
        let session = StoredSession(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            baseURL: URL(string: "https://school.bakalari.cz/")!,
            provider: .bakalari,
            bakalari: BakalariCredentials(username: "filip", password: "school-password")
        )

        let payload = ProviderSecretSanitizer.schoolPayload(from: session)
        let data = try JSONEncoder.sessionEncoder.encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""

        #expect(payload.bakalari?.username == "filip")
        #expect(payload.bakalari?.password == "school-password")
        #expect(json.contains("school-password"))
        #expect(json.contains("filip"))
    }

    @Test func reconnectPrefillUsesLinkedSchoolAndUsernameWithoutPassword() throws {
        var account = PreviewData.linkedSchoolAccount
        account.schoolName = "Soukromá střední škola"
        let session = StoredSession(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            expiresAt: .distantFuture,
            baseURL: URL(string: "https://school.bakalari.cz/")!,
            provider: .bakalari,
            bakalari: BakalariCredentials(username: "filip", password: "secret"),
            linkedAccountID: account.id
        )

        let prefill = try #require(SchoolLoginPrefill(session: session, account: account))

        #expect(prefill.provider == .bakalari)
        #expect(prefill.schoolURL == "https://school.bakalari.cz/")
        #expect(prefill.schoolName == "Soukromá střední škola")
        #expect(prefill.username == "filip")
    }

    @Test func reconnectPrefillRejectsADifferentLinkedAccount() {
        var account = PreviewData.linkedSchoolAccount
        account.id = "other-account"
        let session = StoredSession(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            expiresAt: .distantFuture,
            baseURL: URL(string: "https://school.bakalari.cz/")!,
            provider: .bakalari,
            bakalari: BakalariCredentials(username: "filip", password: "secret"),
            linkedAccountID: "active-account"
        )

        #expect(SchoolLoginPrefill(session: session, account: account) == nil)
    }

    @Test func reconnectAssociatesFreshProviderSessionWithCloudAccount() throws {
        let sessionStore = InMemorySessionStore(
            session: StoredSession(
                accessToken: "fresh-access",
                refreshToken: "fresh-refresh",
                tokenType: "Bearer",
                expiresAt: .distantFuture,
                baseURL: URL(string: "https://school.bakalari.cz/")!,
                provider: .bakalari,
                bakalari: BakalariCredentials(username: "filip", password: "secret")
            )
        )
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: sessionStore,
            marksCache: InMemoryMarksCache()
        )

        try repository.associateCurrentSession(with: PreviewData.linkedSchoolAccount)

        #expect(sessionStore.session?.linkedAccountID == PreviewData.linkedSchoolAccount.id)
        #expect(sessionStore.session?.linkedAccountDisplayName == PreviewData.linkedSchoolAccount.displayName)
        #expect(sessionStore.session?.linkedAccountSchoolName == PreviewData.linkedSchoolAccount.schoolName)
    }

    @Test func newMarkNotificationUsesLockedDefaultCopy() {
        let event = testNewMarkEvent()

        #expect(NewMarkNotificationFormatter.title(for: event) == "New mark")
        #expect(NewMarkNotificationFormatter.body(for: event, preferences: .default) == "1 from TVY")
    }

    @Test func legacyNotificationPreferencesDecodeWithPragueTimeZone() throws {
        let data = Data(
            """
            {
              "newMarksEnabled": false,
              "lockScreenDetail": "full_details",
              "quietHoursEnabled": true,
              "quietHoursStartMinute": 1230,
              "quietHoursEndMinute": 420
            }
            """.utf8
        )

        let preferences = try JSONDecoder().decode(NotificationPreferences.self, from: data)

        #expect(!preferences.newMarksEnabled)
        #expect(preferences.lockScreenDetail == .fullDetails)
        #expect(preferences.quietHoursEnabled)
        #expect(preferences.quietHoursStartMinute == 1230)
        #expect(preferences.quietHoursEndMinute == 420)
        #expect(preferences.quietHoursTimeZoneIdentifier == "Europe/Prague")
    }

    @Test func notificationMinuteConversionAndOvernightWindowUseStoredTimeZone() throws {
        let timeZone = try #require(TimeZone(identifier: "Europe/Prague"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 12)))
        let date = NotificationPreferences.date(forMinuteOfDay: 22 * 60 + 45, on: day, in: timeZone)

        #expect(NotificationPreferences.minuteOfDay(from: date, in: timeZone) == 22 * 60 + 45)

        var preferences = NotificationPreferences.default
        preferences.quietHoursEnabled = true
        #expect(preferences.containsQuietMinute(23 * 60))
        #expect(preferences.containsQuietMinute(5 * 60 + 59))
        #expect(!preferences.containsQuietMinute(12 * 60))
    }

    @Test func notificationPrivacyAndQueuedSummaryUseAppropriateSubjectDetail() {
        let first = testNewMarkEvent(id: "one", subjectAbbrev: "TVY", subjectName: "Telesna vychova")
        let second = testNewMarkEvent(id: "two", subjectAbbrev: "MAT", subjectName: "Matematika")
        var preferences = NotificationPreferences.default

        preferences.lockScreenDetail = .privateSummary
        #expect(NewMarkNotificationFormatter.body(for: first, preferences: preferences) == "Open Gradey to view it")
        #expect(NewMarkNotificationFormatter.summaryBody(for: [first, second], preferences: preferences) == "Open Gradey to view them")

        preferences.lockScreenDetail = .markAndSubject
        #expect(NewMarkNotificationFormatter.body(for: first, preferences: preferences) == "1 from TVY")
        #expect(NewMarkNotificationFormatter.summaryBody(for: [first, second], preferences: preferences) == "2 new marks in TVY, MAT")

        preferences.lockScreenDetail = .fullDetails
        #expect(NewMarkNotificationFormatter.body(for: first, preferences: preferences) == "1 from Telesna vychova")
        #expect(NewMarkNotificationFormatter.summaryBody(for: [first, second], preferences: preferences) == "2 new marks in Telesna vychova, Matematika")
    }

    @MainActor
    @Test func accountSettingsRefreshReplacesCachedValuesWithServerCanonicalValues() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let linkedStore = LinkedAccountStore(userDefaults: defaults)
        let linkedRepository = LinkedAccountRepository(
            store: linkedStore,
            client: MockLinkedAccountClient(),
            authClient: MockGradeyAuthClient()
        )
        linkedRepository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        let preferencesStore = MarkNotificationSettingsStore(userDefaults: defaults)
        preferencesStore.preferences = .default

        var serverAccount = PreviewData.linkedSchoolAccount
        serverAccount.displayName = "Server Student"
        serverAccount.notificationsEnabled = false
        var serverPreferences = NotificationPreferences.default
        serverPreferences.quietHoursEnabled = true
        serverPreferences.quietHoursTimeZoneIdentifier = "America/New_York"
        let settingsClient = MockDevicePushTokenClient(
            accountSettings: GradeyAccountSettingsSnapshot(
                activeSchoolAccountID: serverAccount.id,
                linkedAccounts: [serverAccount],
                notificationPreferences: serverPreferences
            )
        )
        let viewModel = GradeyAccountHubViewModel(
            linkedAccountRepository: linkedRepository,
            notificationClient: settingsClient,
            authClient: MockGradeyAuthClient(),
            preferencesStore: preferencesStore
        )

        await viewModel.refresh()

        #expect(viewModel.accounts == [serverAccount])
        #expect(viewModel.activeSchoolAccountID == serverAccount.id)
        #expect(viewModel.notificationPreferences == serverPreferences)
        #expect(linkedRepository.loadAccounts() == [serverAccount])
        #expect(preferencesStore.preferences == serverPreferences)
    }

    @MainActor
    @Test func accountNameValidationTrimsUnicodeInputAndPersistsImmediately() async throws {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let viewModel = GradeyAccountHubViewModel(
            account: PreviewData.gradeyAuthSession.account,
            linkedAccountRepository: LinkedAccountRepository(
                store: LinkedAccountStore(userDefaults: defaults),
                client: MockLinkedAccountClient(),
                authClient: authClient
            ),
            notificationClient: MockDevicePushTokenClient(),
            authClient: authClient,
            preferencesStore: MarkNotificationSettingsStore(userDefaults: defaults)
        )

        #expect(!viewModel.hasFullNameChanges)
        #expect(!viewModel.canSaveFullName)

        viewModel.updateFullNameDraft("   ")
        #expect(!viewModel.isFullNameValid)
        #expect(!viewModel.canSaveFullName)

        viewModel.updateFullNameDraft(String(repeating: "é", count: 80))
        #expect(viewModel.isFullNameValid)
        viewModel.updateFullNameDraft(String(repeating: "é", count: 81))
        #expect(!viewModel.isFullNameValid)

        viewModel.updateFullNameDraft("  Žofie 👩🏽‍🎓 Nováková  ")
        let savedAccount = await viewModel.saveFullName()
        let updatedAccount = try #require(savedAccount)

        #expect(updatedAccount.fullName == "Žofie 👩🏽‍🎓 Nováková")
        #expect(viewModel.account == updatedAccount)
        #expect(viewModel.fullNameDraft == "Žofie 👩🏽‍🎓 Nováková")
        #expect(authClient.session?.account == updatedAccount)
        #expect(!viewModel.canSaveFullName)
    }

    @MainActor
    @Test func accountNameSaveFailureKeepsDraftAndInlineError() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let originalAccount = PreviewData.gradeyAuthSession.account
        let authClient = MockGradeyAuthClient(
            updateFullNameError: GradeyAuthError.server("Name rejected")
        )
        let viewModel = GradeyAccountHubViewModel(
            account: originalAccount,
            linkedAccountRepository: LinkedAccountRepository(
                store: LinkedAccountStore(userDefaults: defaults),
                client: MockLinkedAccountClient(),
                authClient: authClient
            ),
            notificationClient: MockDevicePushTokenClient(),
            authClient: authClient,
            preferencesStore: MarkNotificationSettingsStore(userDefaults: defaults)
        )

        viewModel.updateFullNameDraft("  Kept Draft  ")
        let updatedAccount = await viewModel.saveFullName()

        #expect(updatedAccount == nil)
        #expect(viewModel.account == originalAccount)
        #expect(viewModel.fullNameDraft == "  Kept Draft  ")
        #expect(viewModel.fullNameErrorMessage == "Name rejected")
        #expect(viewModel.canSaveFullName)
    }

    @MainActor
    @Test func accountRefreshAppliesRemoteProfileAndCachesIt() async throws {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        var remoteAccount = PreviewData.gradeyAuthSession.account
        remoteAccount.fullName = "Remote Name"
        let authClient = MockGradeyAuthClient(remoteAccount: remoteAccount)
        let viewModel = GradeyAccountHubViewModel(
            account: PreviewData.gradeyAuthSession.account,
            linkedAccountRepository: LinkedAccountRepository(
                store: LinkedAccountStore(userDefaults: defaults),
                client: MockLinkedAccountClient(),
                authClient: authClient
            ),
            notificationClient: MockDevicePushTokenClient(),
            authClient: authClient,
            preferencesStore: MarkNotificationSettingsStore(userDefaults: defaults)
        )

        let refreshedResult = await viewModel.refresh()
        let refreshedAccount = try #require(refreshedResult)

        #expect(refreshedAccount == remoteAccount)
        #expect(viewModel.account == remoteAccount)
        #expect(viewModel.fullNameDraft == "Remote Name")
        #expect(authClient.session?.account == remoteAccount)
    }

    @MainActor
    @Test func notificationMutationRollsBackCacheWhenServerRejectsIt() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let preferencesStore = MarkNotificationSettingsStore(userDefaults: defaults)
        let original = NotificationPreferences.default
        preferencesStore.preferences = original
        let settingsClient = MockDevicePushTokenClient(
            updateError: GradeyAuthError.server("Rejected")
        )
        let viewModel = makeAccountHubViewModel(
            defaults: defaults,
            settingsClient: settingsClient,
            preferencesStore: preferencesStore
        )
        var changed = original
        changed.newMarksEnabled = false

        await viewModel.updateNotificationPreferences(changed)

        #expect(viewModel.notificationPreferences == original)
        #expect(preferencesStore.preferences == original)
        #expect(viewModel.errorMessage == "Rejected")
    }

    @MainActor
    @Test func perAccountNotificationMutationRollsBackOnFailure() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let repository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(preferencesError: GradeyAuthError.server("Rejected")),
            authClient: authClient
        )
        repository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        let viewModel = GradeyAccountHubViewModel(
            linkedAccountRepository: repository,
            notificationClient: MockDevicePushTokenClient(),
            authClient: authClient,
            preferencesStore: MarkNotificationSettingsStore(userDefaults: defaults)
        )

        await viewModel.setNotificationsEnabled(false, for: PreviewData.linkedSchoolAccount)

        #expect(viewModel.accounts.first?.notificationsEnabled == true)
        #expect(repository.loadAccounts().first?.notificationsEnabled == true)
        #expect(viewModel.errorMessage == "Rejected")
    }

    @MainActor
    @Test func schoolReconnectUpdatesExistingRowWithoutCreatingDuplicate() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let repository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(),
            authClient: authClient
        )
        repository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        let viewModel = GradeyAccountHubViewModel(
            linkedAccountRepository: repository,
            notificationClient: MockDevicePushTokenClient(),
            authClient: authClient,
            preferencesStore: MarkNotificationSettingsStore(userDefaults: defaults)
        )
        let user = UserResponse(
            userUID: "student-2",
            fullName: "Reconnected Student",
            userClass: nil,
            schoolName: "Demo School",
            userType: "student",
            userTypeText: "Student",
            studyYear: 2026
        )

        let succeeded = await viewModel.reconnect(
            PreviewData.linkedSchoolAccount,
            session: PreviewData.expiredSession,
            user: user
        )

        #expect(succeeded)
        #expect(viewModel.accounts.count == 1)
        #expect(viewModel.accounts.first?.id == PreviewData.linkedSchoolAccount.id)
        #expect(viewModel.accounts.first?.status == .active)
        #expect(viewModel.accounts.first?.actionRequiredReason == nil)
    }

    @MainActor
    @Test func todaySilentlyRelinksWhenLocalProviderSessionStillWorks() async {
        var actionRequired = PreviewData.linkedSchoolAccount
        actionRequired.status = .actionRequired
        actionRequired.actionRequiredReason = "Provider session expired. Re-link this account in Gradey."

        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let linkedClient = MockLinkedAccountClient()
        let linkedRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: linkedClient,
            authClient: authClient
        )
        linkedRepository.replaceLocalAccounts([actionRequired])

        let session = StoredSession(
            accessToken: "local-access",
            refreshToken: "local-refresh",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600),
            baseURL: URL(string: "https://demo.bakalari.cz/")!,
            provider: .bakalari,
            bakalari: BakalariCredentials(username: "filip", password: "secret"),
            linkedAccountID: actionRequired.id
        )
        let viewModel = TodayViewModel(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: InMemorySessionStore(session: session),
                marksCache: InMemoryMarksCache()
            ),
            stravaCZRepository: AppEnvironment.makeMockStravaCZRepository(),
            linkedAccountRepository: linkedRepository,
            historyRepository: GradeyHistoryRepository(
                client: MockGradeyHistoryClient(),
                authClient: authClient
            ),
            accountSettingsClient: MockDevicePushTokenClient(
                accountSettings: GradeyAccountSettingsSnapshot(
                    activeSchoolAccountID: actionRequired.id,
                    linkedAccounts: [actionRequired],
                    notificationPreferences: .default
                )
            ),
            gradeyAuthClient: authClient
        )

        await viewModel.refresh(forceRefresh: false)

        #expect(linkedClient.reconnectCallCount == 1)
        #expect(viewModel.accountRequiringReconnect == nil)
        #expect(linkedRepository.loadAccounts().first?.status == .active)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func todayKeepsReconnectBannerWhenSilentRelinkFails() async {
        var actionRequired = PreviewData.linkedSchoolAccount
        actionRequired.status = .actionRequired
        actionRequired.actionRequiredReason = "Provider session expired. Re-link this account in Gradey."

        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let linkedRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(reconnectError: GradeyAuthError.server("still expired")),
            authClient: authClient
        )
        linkedRepository.replaceLocalAccounts([actionRequired])

        let session = StoredSession(
            accessToken: "local-access",
            refreshToken: "local-refresh",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600),
            baseURL: URL(string: "https://demo.bakalari.cz/")!,
            provider: .bakalari,
            bakalari: BakalariCredentials(username: "filip", password: "secret"),
            linkedAccountID: actionRequired.id
        )
        let viewModel = TodayViewModel(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: InMemorySessionStore(session: session),
                marksCache: InMemoryMarksCache()
            ),
            stravaCZRepository: AppEnvironment.makeMockStravaCZRepository(),
            linkedAccountRepository: linkedRepository,
            historyRepository: GradeyHistoryRepository(
                client: MockGradeyHistoryClient(),
                authClient: authClient
            ),
            accountSettingsClient: MockDevicePushTokenClient(
                accountSettings: GradeyAccountSettingsSnapshot(
                    activeSchoolAccountID: actionRequired.id,
                    linkedAccounts: [actionRequired],
                    notificationPreferences: .default
                )
            ),
            gradeyAuthClient: authClient
        )

        await viewModel.refresh(forceRefresh: false)

        #expect(viewModel.accountRequiringReconnect?.id == actionRequired.id)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func schoolActivationReturnsProviderSessionAndMarksAccountActive() async throws {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let repository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(),
            authClient: authClient
        )
        repository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        let viewModel = GradeyAccountHubViewModel(
            linkedAccountRepository: repository,
            notificationClient: MockDevicePushTokenClient(),
            authClient: authClient,
            preferencesStore: MarkNotificationSettingsStore(userDefaults: defaults)
        )

        let activationResult = await viewModel.activate(PreviewData.linkedSchoolAccount)
        let activation = try #require(activationResult)

        #expect(activation.account.id == PreviewData.linkedSchoolAccount.id)
        #expect(activation.makeStoredSession().linkedAccountID == PreviewData.linkedSchoolAccount.id)
        #expect(viewModel.activeSchoolAccountID == PreviewData.linkedSchoolAccount.id)
    }

    @MainActor
    @Test func dataExportProducesShareableJSONFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GradeyPlatformTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = Data("{\"profile\":{\"id\":\"student\"}}".utf8)
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let settingsClient = MockDevicePushTokenClient(exportData: data)
        let viewModel = GradeyAccountHubViewModel(
            linkedAccountRepository: LinkedAccountRepository(
                store: LinkedAccountStore(userDefaults: defaults),
                client: MockLinkedAccountClient(),
                authClient: MockGradeyAuthClient()
            ),
            notificationClient: settingsClient,
            authClient: MockGradeyAuthClient(),
            preferencesStore: MarkNotificationSettingsStore(userDefaults: defaults),
            exportDirectory: { directory },
            dateProvider: { Date(timeIntervalSince1970: 1_752_332_400) }
        )

        let exportedURL = await viewModel.exportData()
        let url = try #require(exportedURL)

        #expect(url.pathExtension == "json")
        #expect(try Data(contentsOf: url) == data)
        #expect(settingsClient.didRequestDataExport)
    }

    @MainActor
    @Test func successfulAccountDeletionClearsHubCaches() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let repository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(),
            authClient: authClient
        )
        repository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        let preferencesStore = MarkNotificationSettingsStore(userDefaults: defaults)
        var changedPreferences = NotificationPreferences.default
        changedPreferences.newMarksEnabled = false
        preferencesStore.preferences = changedPreferences
        let settingsClient = MockDevicePushTokenClient()
        let viewModel = GradeyAccountHubViewModel(
            linkedAccountRepository: repository,
            notificationClient: settingsClient,
            authClient: authClient,
            preferencesStore: preferencesStore
        )

        let succeeded = await viewModel.deleteAccount()

        #expect(succeeded)
        #expect(settingsClient.didDeleteAccount)
        #expect(viewModel.accounts.isEmpty)
        #expect(repository.loadAccounts().isEmpty)
        #expect(preferencesStore.preferences == .default)
    }

    @MainActor
    @Test func failedAccountDeletionKeepsLocalStateForRetry() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let repository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(),
            authClient: authClient
        )
        repository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        let preferencesStore = MarkNotificationSettingsStore(userDefaults: defaults)
        var changedPreferences = NotificationPreferences.default
        changedPreferences.newMarksEnabled = false
        preferencesStore.preferences = changedPreferences
        let viewModel = GradeyAccountHubViewModel(
            linkedAccountRepository: repository,
            notificationClient: MockDevicePushTokenClient(
                deleteError: GradeyAuthError.server("Try again")
            ),
            authClient: authClient,
            preferencesStore: preferencesStore
        )

        let succeeded = await viewModel.deleteAccount()

        #expect(!succeeded)
        #expect(repository.loadAccounts() == [PreviewData.linkedSchoolAccount])
        #expect(preferencesStore.preferences == changedPreferences)
        #expect(viewModel.errorMessage == "Try again")
    }

    @MainActor
    @Test func accountSettingsClientDecodesCanonicalResponseAndSendsSnakeCasePreferences() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountSettingsURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let client = SupabaseDevicePushTokenClient(
            configuration: SupabaseConfiguration(
                url: URL(string: "https://project-ref.supabase.co")!,
                anonKey: "sb_publishable_test"
            ),
            urlSession: urlSession
        )
        let session = PreviewData.gradeyAuthSession
        AccountSettingsURLProtocol.responseData = Data(
            """
            {
              "profile": { "id": "student" },
              "active_school_account_id": "school-id",
              "linked_accounts": [
                {
                  "id": "school-id",
                  "provider": "bakalari",
                  "providerUserID": "student",
                  "displayName": "Student",
                  "schoolName": "School",
                  "canteenName": null,
                  "status": "active",
                  "notificationsEnabled": true,
                  "lastPolledAt": null,
                  "lastSyncedAt": "2026-07-18T21:22:33.123Z",
                  "actionRequiredReason": null
                }
              ],
              "notification_preferences": {
                "new_marks_enabled": true,
                "lock_screen_detail": "mark_and_subject",
                "quiet_hours_enabled": true,
                "quiet_hours_start_minute": 1320,
                "quiet_hours_end_minute": 360,
                "quiet_hours_time_zone": "Europe/Prague"
              }
            }
            """.utf8
        )
        defer { AccountSettingsURLProtocol.reset() }

        let snapshot = try await client.fetchAccountSettings(gradeySession: session)

        #expect(snapshot.activeSchoolAccountID == "school-id")
        #expect(snapshot.linkedAccounts.first?.lastSyncedAt != nil)
        #expect(snapshot.notificationPreferences.quietHoursTimeZoneIdentifier == "Europe/Prague")
        #expect(AccountSettingsURLProtocol.lastRequest?.httpMethod == "GET")
        #expect(AccountSettingsURLProtocol.lastRequest?.url?.path == "/functions/v1/account-settings")

        AccountSettingsURLProtocol.responseData = Data(
            """
            {
              "notification_preferences": {
                "new_marks_enabled": false,
                "lock_screen_detail": "full_details",
                "quiet_hours_enabled": true,
                "quiet_hours_start_minute": 1260,
                "quiet_hours_end_minute": 420,
                "quiet_hours_time_zone": "America/New_York"
              }
            }
            """.utf8
        )
        var preferences = NotificationPreferences.default
        preferences.newMarksEnabled = false
        preferences.lockScreenDetail = .fullDetails
        preferences.quietHoursEnabled = true
        preferences.quietHoursStartMinute = 1260
        preferences.quietHoursEndMinute = 420
        preferences.quietHoursTimeZoneIdentifier = "America/New_York"

        let canonical = try await client.updateNotificationPreferences(preferences, gradeySession: session)
        let requestBody = try #require(AccountSettingsURLProtocol.lastRequestBody)
        let requestJSON = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])

        #expect(canonical.quietHoursTimeZoneIdentifier == "America/New_York")
        #expect(AccountSettingsURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(AccountSettingsURLProtocol.lastRequest?.url?.path == "/functions/v1/update-notification-preferences")
        #expect(requestJSON["quiet_hours_time_zone"] as? String == "America/New_York")
        #expect(requestJSON["new_marks_enabled"] as? Bool == false)

        // The previously deployed function accepted the mutation but returned
        // an empty object instead of the canonical response envelope.
        AccountSettingsURLProtocol.responseData = Data("{}".utf8)
        let returned = try await client.updateNotificationPreferences(
            preferences,
            gradeySession: session
        )
        #expect(returned == preferences)

        // Preserve the platform metadata so background refresh can distinguish
        // a missing deployment from a user-initiated mutation failure.
        AccountSettingsURLProtocol.statusCode = 404
        AccountSettingsURLProtocol.responseData = Data(
            #"{"code":"NOT_FOUND","message":"Requested function was not found"}"#.utf8
        )

        do {
            _ = try await client.fetchAccountSettings(gradeySession: session)
            Issue.record("Expected the missing Edge Function response to throw")
        } catch let error as GradeyFunctionError {
            #expect(error == .httpStatus(
                function: "account-settings",
                statusCode: 404,
                code: "NOT_FOUND",
                message: "Requested function was not found"
            ))
            #expect(error.isUnavailableCapability)
        }
    }

    @MainActor
    @Test func accountSettingsRefreshFailureKeepsCachedStateWithoutBlockingAlert() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let linkedRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(),
            authClient: authClient
        )
        linkedRepository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        let preferencesStore = MarkNotificationSettingsStore(userDefaults: defaults)
        var cachedPreferences = NotificationPreferences.default
        cachedPreferences.newMarksEnabled = false
        preferencesStore.preferences = cachedPreferences
        let viewModel = GradeyAccountHubViewModel(
            linkedAccountRepository: linkedRepository,
            notificationClient: MockDevicePushTokenClient(
                fetchError: GradeyFunctionError.httpStatus(
                    function: "account-settings",
                    statusCode: 404,
                    code: "NOT_FOUND",
                    message: "Requested function was not found"
                )
            ),
            authClient: authClient,
            preferencesStore: preferencesStore
        )

        await viewModel.refresh()

        #expect(viewModel.accounts == [PreviewData.linkedSchoolAccount])
        #expect(viewModel.notificationPreferences == cachedPreferences)
        #expect(linkedRepository.loadAccounts() == [PreviewData.linkedSchoolAccount])
        #expect(viewModel.isUsingCachedSettings)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func bootstrapRestoresCanonicalActiveSchoolAndEntersTodayState() async throws {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let schoolSessionStore = InMemorySessionStore()
        let schoolRepository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: schoolSessionStore,
            marksCache: InMemoryMarksCache()
        )
        let authClient = MockGradeyAuthClient()
        let linkedRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(),
            authClient: authClient
        )
        var canonicalPreferences = NotificationPreferences.default
        canonicalPreferences.quietHoursEnabled = true
        let accountSettingsClient = MockDevicePushTokenClient(
            accountSettings: GradeyAccountSettingsSnapshot(
                activeSchoolAccountID: PreviewData.linkedSchoolAccount.id,
                linkedAccounts: [PreviewData.linkedSchoolAccount],
                notificationPreferences: canonicalPreferences
            )
        )
        let preferencesStore = MarkNotificationSettingsStore(userDefaults: defaults)
        let viewModel = AppViewModel(
            repository: schoolRepository,
            stravaCZRepository: AppEnvironment.makeMockStravaCZRepository(),
            gradeyAuthClient: authClient,
            linkedAccountRepository: linkedRepository,
            accountSettingsClient: accountSettingsClient,
            notificationSettingsStore: preferencesStore,
            guestModeStore: InMemoryGradeyGuestModeStore(),
            requiresGradeyID: true
        )

        await viewModel.bootstrap()

        #expect(viewModel.phase == .signedIn)
        #expect(viewModel.gradeyAccount == PreviewData.gradeyAuthSession.account)
        #expect(schoolSessionStore.session?.linkedAccountID == PreviewData.linkedSchoolAccount.id)
        #expect(linkedRepository.loadAccounts().first?.id == PreviewData.linkedSchoolAccount.id)
        #expect(preferencesStore.preferences == canonicalPreferences)
    }

    @MainActor
    @Test func bootstrapKeepsGradeySessionWhenCanonicalSchoolCannotBeActivated() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let linkedRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(activationError: URLError(.notConnectedToInternet)),
            authClient: authClient
        )
        let accountSettingsClient = MockDevicePushTokenClient(
            accountSettings: GradeyAccountSettingsSnapshot(
                activeSchoolAccountID: PreviewData.linkedSchoolAccount.id,
                linkedAccounts: [PreviewData.linkedSchoolAccount],
                notificationPreferences: .default
            )
        )
        let viewModel = AppViewModel(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: InMemorySessionStore(),
                marksCache: InMemoryMarksCache()
            ),
            stravaCZRepository: AppEnvironment.makeMockStravaCZRepository(),
            gradeyAuthClient: authClient,
            linkedAccountRepository: linkedRepository,
            accountSettingsClient: accountSettingsClient,
            notificationSettingsStore: MarkNotificationSettingsStore(userDefaults: defaults),
            guestModeStore: InMemoryGradeyGuestModeStore(),
            requiresGradeyID: true
        )

        await viewModel.bootstrap()

        #expect(viewModel.phase == .signedInNeedsSchool)
        #expect(authClient.session != nil)
        #expect(linkedRepository.loadAccounts() == [PreviewData.linkedSchoolAccount])
    }

    @MainActor
    @Test func guestModeSkipsGradeyGateAndPersistsTheChoice() async {
        let gradeyAuthClient = MockGradeyAuthClient(session: nil)
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache()
        )
        let linkedAccountRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!),
            client: MockLinkedAccountClient(),
            authClient: gradeyAuthClient
        )
        let guestModeStore = InMemoryGradeyGuestModeStore()
        let viewModel = AppViewModel(
            repository: repository,
            stravaCZRepository: AppEnvironment.makeMockStravaCZRepository(),
            gradeyAuthClient: gradeyAuthClient,
            linkedAccountRepository: linkedAccountRepository,
            guestModeStore: guestModeStore,
            requiresGradeyID: true
        )

        await viewModel.bootstrap()
        #expect(viewModel.usesGradeyIDGate)
        #expect(viewModel.phase == .signedOut)

        await viewModel.continueWithoutAccount()
        #expect(!viewModel.usesGradeyIDGate)
        #expect(viewModel.isGuestMode)
        #expect(guestModeStore.isEnabled)
        #expect(viewModel.phase == .signedInNeedsSchool)
    }

    @MainActor
    @Test func gradeyIDViewModelKeepsOnboardingAtAccountAfterAppleSignInFailure() async {
        let viewModel = GradeyIDViewModel(
            authClient: MockGradeyAuthClient(
                session: nil,
                signInError: GradeyAuthError.server("Sign in failed.")
            )
        )

        let didSignIn = await viewModel.signInWithApple(
            identityToken: "invalid-token",
            nonce: nil,
            fullName: nil
        )

        #expect(!didSignIn)
        #expect(!viewModel.isLoading)
        #expect(viewModel.errorMessage == "Sign in failed.")
    }

    @MainActor
    @Test func upgradeGuestContinuationPreservesProviderSessionsAndCaches() async throws {
        let schoolSessionStore = InMemorySessionStore(session: PreviewData.expiredSession)
        let schoolCache = InMemoryMarksCache(
            cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date())
        )
        let mealsSessionStore = InMemoryStravaCZSessionStore(session: PreviewData.stravaCZSession)
        let cachedMeals = CachedStravaCZMenu(
            menu: StravaCZMenu.make(from: PreviewData.stravaCZMenuResponse),
            cachedAt: Date()
        )
        let mealsCache = InMemoryStravaCZMenuCache(cachedMenu: cachedMeals)
        let viewModel = AppViewModel(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: schoolSessionStore,
                marksCache: schoolCache
            ),
            stravaCZRepository: StravaCZRepository(
                client: MockStravaCZClient(),
                sessionStore: mealsSessionStore,
                menuCache: mealsCache
            ),
            gradeyAuthClient: MockGradeyAuthClient(session: nil),
            linkedAccountRepository: LinkedAccountRepository(
                store: LinkedAccountStore(
                    userDefaults: UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
                ),
                client: MockLinkedAccountClient(),
                authClient: MockGradeyAuthClient(session: nil)
            ),
            guestModeStore: InMemoryGradeyGuestModeStore(),
            requiresGradeyID: true
        )

        await viewModel.continueWithoutAccount()

        #expect(try schoolSessionStore.loadSession() == PreviewData.expiredSession)
        #expect(try schoolCache.load()?.marksResponse == PreviewData.marksResponse)
        #expect(try mealsSessionStore.loadSession() == PreviewData.stravaCZSession)
        #expect(try mealsCache.load() == cachedMeals)
        #expect(viewModel.phase == .signedIn)
    }

    @MainActor
    @Test func refreshedGradeyAccountPropagatesIntoAppViewModelImmediately() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let authClient = MockGradeyAuthClient()
        let linkedAccountRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(),
            authClient: authClient
        )
        let viewModel = AppViewModel(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: InMemorySessionStore(),
                marksCache: InMemoryMarksCache()
            ),
            stravaCZRepository: AppEnvironment.makeMockStravaCZRepository(),
            gradeyAuthClient: authClient,
            linkedAccountRepository: linkedAccountRepository,
            guestModeStore: InMemoryGradeyGuestModeStore(),
            requiresGradeyID: true
        )
        await viewModel.bootstrap()

        var renamedAccount = PreviewData.gradeyAuthSession.account
        renamedAccount.fullName = "Immediately Updated"
        viewModel.updateGradeyAccount(renamedAccount)

        #expect(viewModel.gradeyAccount == renamedAccount)

        var mismatchedAccount = renamedAccount
        mismatchedAccount = GradeyAccount(
            id: "different-user",
            email: mismatchedAccount.email,
            fullName: "Wrong User",
            avatarURL: mismatchedAccount.avatarURL,
            createdAt: mismatchedAccount.createdAt
        )
        viewModel.updateGradeyAccount(mismatchedAccount)
        #expect(viewModel.gradeyAccount == renamedAccount)
    }

    @MainActor
    @Test func persistedGuestModeClearsStaleGradeySessionAndCloudCache() async {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let gradeyAuthClient = MockGradeyAuthClient()
        let linkedAccountRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(),
            authClient: gradeyAuthClient
        )
        linkedAccountRepository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        let preferencesStore = MarkNotificationSettingsStore(userDefaults: defaults)
        var changedPreferences = NotificationPreferences.default
        changedPreferences.newMarksEnabled = false
        preferencesStore.preferences = changedPreferences
        let viewModel = AppViewModel(
            repository: SchoolRepository(
                client: MockBakalariClient(),
                sessionStore: InMemorySessionStore(),
                marksCache: InMemoryMarksCache()
            ),
            stravaCZRepository: AppEnvironment.makeMockStravaCZRepository(),
            gradeyAuthClient: gradeyAuthClient,
            linkedAccountRepository: linkedAccountRepository,
            notificationSettingsStore: preferencesStore,
            guestModeStore: InMemoryGradeyGuestModeStore(isEnabled: true),
            requiresGradeyID: true
        )

        await viewModel.bootstrap()

        #expect(gradeyAuthClient.session == nil)
        #expect(linkedAccountRepository.loadAccounts().isEmpty)
        #expect(preferencesStore.preferences == .default)
        #expect(viewModel.phase == .signedInNeedsSchool)
    }

    @MainActor
    @Test func globalSignOutClearsProviderSessionsAccountCacheAndPreferences() async throws {
        let defaults = UserDefaults(suiteName: "GradeyPlatformTests.\(UUID().uuidString)")!
        let schoolSessionStore = InMemorySessionStore(session: PreviewData.expiredSession)
        let marksCache = InMemoryMarksCache(
            cachedMarks: CachedMarks(marksResponse: PreviewData.marksResponse, cachedAt: Date())
        )
        let schoolRepository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: schoolSessionStore,
            marksCache: marksCache
        )
        let mealsSessionStore = InMemoryStravaCZSessionStore(session: PreviewData.stravaCZSession)
        let mealsCache = InMemoryStravaCZMenuCache(
            cachedMenu: CachedStravaCZMenu(
                menu: StravaCZMenu.make(from: PreviewData.stravaCZMenuResponse),
                cachedAt: Date()
            )
        )
        let mealsRepository = StravaCZRepository(
            client: MockStravaCZClient(),
            sessionStore: mealsSessionStore,
            menuCache: mealsCache
        )
        let authClient = MockGradeyAuthClient()
        let linkedRepository = LinkedAccountRepository(
            store: LinkedAccountStore(userDefaults: defaults),
            client: MockLinkedAccountClient(),
            authClient: authClient
        )
        linkedRepository.replaceLocalAccounts([PreviewData.linkedSchoolAccount])
        let preferencesStore = MarkNotificationSettingsStore(userDefaults: defaults)
        var changedPreferences = NotificationPreferences.default
        changedPreferences.newMarksEnabled = false
        preferencesStore.preferences = changedPreferences
        let guestModeStore = InMemoryGradeyGuestModeStore(isEnabled: true)
        let viewModel = AppViewModel(
            repository: schoolRepository,
            stravaCZRepository: mealsRepository,
            gradeyAuthClient: authClient,
            linkedAccountRepository: linkedRepository,
            notificationSettingsStore: preferencesStore,
            guestModeStore: guestModeStore,
            requiresGradeyID: true
        )

        await viewModel.signOut()

        #expect(try schoolSessionStore.loadSession() == nil)
        #expect(marksCache.cachedMarks == nil)
        #expect(try mealsSessionStore.loadSession() == nil)
        #expect(try mealsCache.load() == nil)
        #expect(authClient.session == nil)
        #expect(linkedRepository.loadAccounts().isEmpty)
        #expect(preferencesStore.preferences == .default)
        #expect(!guestModeStore.isEnabled)
        #expect(viewModel.phase == .signedOut)
    }

    private func testSubject(id: String, abbrev: String) -> Subject {
        Subject(
            marks: [],
            subjectInfo: SubjectInfo(id: id, abbrev: abbrev, name: "Subject"),
            averageText: nil
        )
    }

    private func testMark(id: String, subjectID: String, markText: String) -> Mark {
        Mark(
            markDate: "2026-06-30T00:00:00+02:00",
            caption: "Test",
            markText: markText,
            type: "grade",
            weight: 1,
            subjectID: subjectID,
            id: id
        )
    }

    private func testNewMarkEvent(
        id: String = "event",
        subjectAbbrev: String = "TVY",
        subjectName: String = "Telesna vychova"
    ) -> NewMarkEvent {
        NewMarkEvent(
            id: id,
            linkedAccountID: "account",
            provider: .bakalari,
            subjectID: "subj-\(id)",
            subjectAbbrev: subjectAbbrev,
            subjectName: subjectName,
            markText: "1",
            fingerprint: MarkFingerprint(
                provider: .bakalari,
                linkedAccountID: "account",
                subjectID: "subj-\(id)",
                providerMarkID: "mark-\(id)",
                value: "fingerprint-\(id)",
                source: .providerID
            ),
            createdAt: Date(),
            deliveredAt: nil
        )
    }

    @MainActor
    private func makeAccountHubViewModel(
        defaults: UserDefaults,
        settingsClient: MockDevicePushTokenClient,
        preferencesStore: MarkNotificationSettingsStore
    ) -> GradeyAccountHubViewModel {
        let authClient = MockGradeyAuthClient()
        return GradeyAccountHubViewModel(
            linkedAccountRepository: LinkedAccountRepository(
                store: LinkedAccountStore(userDefaults: defaults),
                client: MockLinkedAccountClient(),
                authClient: authClient
            ),
            notificationClient: settingsClient,
            authClient: authClient,
            preferencesStore: preferencesStore
        )
    }
}

private final class AccountSettingsURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? Self.readBodyStream(from: request)
        guard let url = request.url, let responseData = Self.responseData else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    nonisolated static func reset() {
        responseData = nil
        statusCode = 200
        lastRequest = nil
        lastRequestBody = nil
    }

    nonisolated private static func readBodyStream(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
