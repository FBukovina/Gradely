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
    var accounts: [LinkedAccount] = []
    var notificationPreferences: NotificationPreferences
    var errorMessage: String?

    private let linkedAccountRepository: LinkedAccountRepository
    private let notificationClient: any DevicePushTokenClient
    private let authClient: any GradeyAuthClient
    private let preferencesStore: MarkNotificationSettingsStore

    init(
        linkedAccountRepository: LinkedAccountRepository,
        notificationClient: any DevicePushTokenClient,
        authClient: any GradeyAuthClient,
        preferencesStore: MarkNotificationSettingsStore
    ) {
        self.linkedAccountRepository = linkedAccountRepository
        self.notificationClient = notificationClient
        self.authClient = authClient
        self.preferencesStore = preferencesStore
        notificationPreferences = preferencesStore.preferences
        accounts = linkedAccountRepository.loadAccounts()
    }

    func reload() {
        accounts = linkedAccountRepository.loadAccounts()
        notificationPreferences = preferencesStore.preferences
    }

    func linkSchool(session: StoredSession, user: UserResponse?) async {
        do {
            _ = try await linkedAccountRepository.linkCurrentSchoolAccount(session: session, user: user)
            reload()
            await PushRegistrationService.shared.requestAuthorizationAfterFirstLink()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func linkStravaCZ(session: StravaCZStoredSession) async {
        do {
            _ = try await linkedAccountRepository.linkCurrentStravaCZAccount(session: session)
            reload()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) async {
        notificationPreferences = preferences
        preferencesStore.preferences = preferences

        guard let session = try? authClient.bootstrapSession() else { return }
        do {
            try await notificationClient.updateNotificationPreferences(preferences, gradeySession: session)
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func unlink(_ account: LinkedAccount) async {
        do {
            try await linkedAccountRepository.unlinkAccount(id: account.id)
            reload()
        } catch {
            errorMessage = userFacingMessage(for: error)
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
