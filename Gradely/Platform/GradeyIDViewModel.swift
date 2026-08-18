import Foundation
import Observation

@MainActor
@Observable
final class GradeyIDViewModel {
    var isLoading = false
    var errorMessage: String?

    private let authClient: any GradeyAuthClient

    init(authClient: any GradeyAuthClient) {
        self.authClient = authClient
    }

    func signInWithApple(identityToken: String, nonce: String?, fullName: String?) async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await authClient.signInWithApple(identityToken: identityToken, nonce: nonce, fullName: fullName)
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}

@MainActor
@Observable
final class GradeyAccountHubViewModel {
    var account: GradeyAccount?
    var accounts: [LinkedAccount] = []
    var notificationPreferences: NotificationPreferences
    var activeSchoolAccountID: String?
    var errorMessage: String?
    var fullNameDraft: String
    var fullNameErrorMessage: String?
    var isRefreshing = false
    var isUsingCachedSettings = false
    var isUpdatingFullName = false
    var isExporting = false
    var isDeletingAccount = false
    var mutatingAccountIDs: Set<String> = []

    private var hasEditedFullNameDraft = false
    private let linkedAccountRepository: LinkedAccountRepository
    private let notificationClient: any DevicePushTokenClient
    private let authClient: any GradeyAuthClient
    private let preferencesStore: MarkNotificationSettingsStore
    private let exportDirectory: () -> URL
    private let dateProvider: () -> Date

    init(
        account: GradeyAccount? = nil,
        linkedAccountRepository: LinkedAccountRepository,
        notificationClient: any DevicePushTokenClient,
        authClient: any GradeyAuthClient,
        preferencesStore: MarkNotificationSettingsStore,
        exportDirectory: @escaping () -> URL = { FileManager.default.temporaryDirectory },
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.linkedAccountRepository = linkedAccountRepository
        self.notificationClient = notificationClient
        self.authClient = authClient
        self.preferencesStore = preferencesStore
        self.exportDirectory = exportDirectory
        self.dateProvider = dateProvider
        self.account = account
        fullNameDraft = account?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        notificationPreferences = preferencesStore.preferences
        accounts = linkedAccountRepository.loadAccounts()
    }

    func reload() {
        accounts = linkedAccountRepository.loadAccounts()
        notificationPreferences = preferencesStore.preferences
    }

    @discardableResult
    func refresh() async -> GradeyAccount? {
        errorMessage = nil
        isUsingCachedSettings = false
        isRefreshing = true
        defer { isRefreshing = false }

        var refreshedAccount: GradeyAccount?
        do {
            let canonicalAccount = try await authClient.refreshAccount()
            applyAccount(canonicalAccount)
            refreshedAccount = canonicalAccount
        } catch AppError.notLoggedIn {
            // Guest mode and signed-out previews do not have a remote profile.
        } catch {
            // Profile refresh is opportunistic. Keep the Keychain-backed account
            // supplied at launch if the network is unavailable.
            isUsingCachedSettings = true
        }

        do {
            let session = try await authClient.validSession()
            let snapshot = try await notificationClient.fetchAccountSettings(gradeySession: session)
            activeSchoolAccountID = snapshot.activeSchoolAccountID
            accounts = snapshot.linkedAccounts
            notificationPreferences = snapshot.notificationPreferences
            linkedAccountRepository.replaceLocalAccounts(snapshot.linkedAccounts)
            preferencesStore.preferences = snapshot.notificationPreferences
        } catch AppError.notLoggedIn {
            // Guest mode and signed-out previews intentionally keep their local snapshot.
        } catch {
            // Refresh is opportunistic. Keep the immediately available cache
            // when the device is offline or the backend is mid-rollout; only
            // user-initiated mutations should interrupt the user with an alert.
            isUsingCachedSettings = true
        }

        return refreshedAccount
    }

    var trimmedFullName: String {
        fullNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isFullNameValid: Bool {
        (1...80).contains(trimmedFullName.count)
    }

    var hasFullNameChanges: Bool {
        trimmedFullName != (account?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    var canSaveFullName: Bool {
        isFullNameValid && hasFullNameChanges && !isUpdatingFullName
    }

    func updateFullNameDraft(_ value: String) {
        fullNameDraft = value
        fullNameErrorMessage = nil
        hasEditedFullNameDraft = true
    }

    @discardableResult
    func saveFullName() async -> GradeyAccount? {
        guard canSaveFullName else { return nil }

        fullNameErrorMessage = nil
        isUpdatingFullName = true
        defer { isUpdatingFullName = false }

        do {
            let updatedAccount = try await authClient.updateFullName(trimmedFullName)
            applyAccount(updatedAccount, resetDraft: true)
            return updatedAccount
        } catch {
            fullNameErrorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    func linkSchool(session: StoredSession, user: UserResponse?) async -> LinkedAccount? {
        errorMessage = nil
        do {
            let account = try await linkedAccountRepository.linkCurrentSchoolAccount(session: session, user: user)
            reload()
            if activeSchoolAccountID == nil {
                activeSchoolAccountID = account.id
            }
            return account
        } catch {
            errorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    func linkStravaCZ(session: StravaCZStoredSession) async -> Bool {
        errorMessage = nil
        do {
            _ = try await linkedAccountRepository.linkCurrentStravaCZAccount(session: session)
            reload()
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) async {
        errorMessage = nil
        let previous = notificationPreferences
        let prepared = preferences.preparedForServerUpdate()
        notificationPreferences = prepared
        preferencesStore.preferences = prepared

        do {
            let session = try await authClient.validSession()
            let canonical = try await notificationClient.updateNotificationPreferences(
                prepared,
                gradeySession: session
            )
            notificationPreferences = canonical
            preferencesStore.preferences = canonical
        } catch {
            notificationPreferences = previous
            preferencesStore.preferences = previous
            errorMessage = userFacingMessage(for: error)
        }
    }

    func activate(_ account: LinkedAccount) async -> LinkedSchoolAccountActivation? {
        errorMessage = nil
        mutatingAccountIDs.insert(account.id)
        defer { mutatingAccountIDs.remove(account.id) }

        do {
            let activation = try await linkedAccountRepository.activateSchoolAccount(id: account.id)
            accounts = linkedAccountRepository.loadAccounts()
            activeSchoolAccountID = activation.account.id
            return activation
        } catch {
            errorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    func reconnect(
        _ account: LinkedAccount,
        session: StoredSession,
        user: UserResponse?
    ) async -> Bool {
        errorMessage = nil
        mutatingAccountIDs.insert(account.id)
        defer { mutatingAccountIDs.remove(account.id) }

        do {
            _ = try await linkedAccountRepository.reconnectSchoolAccount(
                id: account.id,
                session: session,
                user: user
            )
            accounts = linkedAccountRepository.loadAccounts()
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func setNotificationsEnabled(_ enabled: Bool, for account: LinkedAccount) async {
        errorMessage = nil
        let previous = accounts
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index].notificationsEnabled = enabled
            linkedAccountRepository.replaceLocalAccounts(accounts)
        }

        mutatingAccountIDs.insert(account.id)
        defer { mutatingAccountIDs.remove(account.id) }

        do {
            _ = try await linkedAccountRepository.updateNotificationsEnabled(
                id: account.id,
                enabled: enabled
            )
            accounts = linkedAccountRepository.loadAccounts()
        } catch {
            accounts = previous
            linkedAccountRepository.replaceLocalAccounts(previous)
            errorMessage = userFacingMessage(for: error)
        }
    }

    func exportData() async -> URL? {
        errorMessage = nil
        isExporting = true
        defer { isExporting = false }

        do {
            let session = try await authClient.validSession()
            let data = try await notificationClient.requestDataExport(gradeySession: session)
            _ = try JSONSerialization.jsonObject(with: data)
            let url = exportDirectory().appendingPathComponent(exportFileName(), isDirectory: false)
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            errorMessage = userFacingMessage(for: error)
            return nil
        }
    }

    func deleteAccount() async -> Bool {
        errorMessage = nil
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            let session = try await authClient.validSession()
            try await notificationClient.deleteAccount(gradeySession: session)
            linkedAccountRepository.clearLocalAccounts()
            preferencesStore.clear()
            accounts = []
            notificationPreferences = .default
            activeSchoolAccountID = nil
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func unlink(_ account: LinkedAccount) async {
        errorMessage = nil
        mutatingAccountIDs.insert(account.id)
        defer { mutatingAccountIDs.remove(account.id) }
        do {
            try await linkedAccountRepository.unlinkAccount(id: account.id)
            reload()
            if activeSchoolAccountID == account.id {
                activeSchoolAccountID = nil
            }
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func isMutating(_ account: LinkedAccount) -> Bool {
        mutatingAccountIDs.contains(account.id)
    }

    private func applyAccount(_ updatedAccount: GradeyAccount, resetDraft: Bool = false) {
        account = updatedAccount
        guard resetDraft || !hasEditedFullNameDraft else { return }
        fullNameDraft = updatedAccount.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasEditedFullNameDraft = false
    }

    private func exportFileName() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dateProvider())
        return String(
            format: "Gradey-Data-Export-%04d%02d%02d-%02d%02d%02d.json",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
