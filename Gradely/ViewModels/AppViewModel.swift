import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    enum Phase: Equatable {
        case checking
        case signedOut
        case signedInNeedsSchool
        case signedIn
    }

    private let repository: SchoolRepository
    private let stravaCZRepository: StravaCZRepository
    private let gradeyAuthClient: any GradeyAuthClient
    private let linkedAccountRepository: LinkedAccountRepository
    private let accountSettingsClient: (any GradeyAccountSettingsClient)?
    private let notificationSettingsStore: MarkNotificationSettingsStore
    private let guestModeStore: any GradeyGuestModeStoring
    private let requiresGradeyID: Bool

    var phase: Phase = .checking
    var gradeyAccount: GradeyAccount?
    private(set) var isGuestMode: Bool

    var usesGradeyIDGate: Bool {
        requiresGradeyID && !isGuestMode
    }

    init(
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        gradeyAuthClient: any GradeyAuthClient,
        linkedAccountRepository: LinkedAccountRepository,
        accountSettingsClient: (any GradeyAccountSettingsClient)? = nil,
        notificationSettingsStore: MarkNotificationSettingsStore? = nil,
        guestModeStore: any GradeyGuestModeStoring = GradeyGuestModeStore(),
        requiresGradeyID: Bool
    ) {
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.gradeyAuthClient = gradeyAuthClient
        self.linkedAccountRepository = linkedAccountRepository
        self.accountSettingsClient = accountSettingsClient
        self.notificationSettingsStore = notificationSettingsStore ?? MarkNotificationSettingsStore()
        self.guestModeStore = guestModeStore
        self.requiresGradeyID = requiresGradeyID
        isGuestMode = guestModeStore.isEnabled
    }

    func bootstrap() async {
        if isGuestMode {
            await RevenueCatIdentity.reset()
            await gradeyAuthClient.signOut()
            linkedAccountRepository.clearLocalAccounts()
            notificationSettingsStore.clear()
            gradeyAccount = nil
        }

        do {
            var gradeySession: GradeyAuthSession?
            if usesGradeyIDGate {
                guard let restoredGradeySession = try gradeyAuthClient.bootstrapSession() else {
                    gradeyAccount = nil
                    phase = .signedOut
                    return
                }
                gradeySession = restoredGradeySession
                gradeyAccount = restoredGradeySession.account
                await RevenueCatIdentity.identify(userID: restoredGradeySession.account.id)
            }

            if try repository.bootstrapSession() != nil {
                phase = .signedIn
                return
            }

            if let gradeySession,
               await restoreActiveSchoolSession(using: gradeySession) {
                phase = .signedIn
                return
            }

            phase = .signedInNeedsSchool
        } catch {
            phase = .signedOut
        }
    }

    func markGradeySignedIn() async {
        guestModeStore.isEnabled = false
        isGuestMode = false
        gradeyAccount = try? gradeyAuthClient.bootstrapSession()?.account
        await bootstrap()
        await PushRegistrationService.shared.refreshRegistrationIfAuthorized()
    }

    func continueWithoutAccount() async {
        await RevenueCatIdentity.reset()
        await gradeyAuthClient.signOut()
        linkedAccountRepository.clearLocalAccounts()
        notificationSettingsStore.clear()
        guestModeStore.isEnabled = true
        isGuestMode = true
        gradeyAccount = nil
        await bootstrap()
    }

    func leaveGuestMode() {
        guestModeStore.isEnabled = false
        isGuestMode = false
        gradeyAccount = nil
        phase = .signedOut
    }

    func markSignedIn() {
        phase = .signedIn
    }

    func markNeedsSchool() {
        phase = .signedInNeedsSchool
    }

    func updateGradeyAccount(_ account: GradeyAccount) {
        guard !isGuestMode, gradeyAccount == nil || gradeyAccount?.id == account.id else { return }
        gradeyAccount = account
    }

    func signOut() async {
        await stravaCZRepository.logout()
        await RevenueCatIdentity.reset()
        await gradeyAuthClient.signOut()
        linkedAccountRepository.clearLocalAccounts()
        notificationSettingsStore.clear()
        try? repository.logout()
        guestModeStore.isEnabled = false
        isGuestMode = false
        gradeyAccount = nil
        phase = .signedOut
    }

    func signOutOfSchool() async {
        await stravaCZRepository.logout()
        try? repository.logout()
        phase = .signedInNeedsSchool
    }

    func clearLocalCaches() {
        try? repository.clearLocalCaches()
        stravaCZRepository.clearCachedMenu()
    }

    func resetAsNewUser() async {
        await signOut()
        clearLocalCaches()
    }

    private func restoreActiveSchoolSession(using gradeySession: GradeyAuthSession) async -> Bool {
        guard let accountSettingsClient else { return false }

        do {
            let snapshot = try await accountSettingsClient.fetchAccountSettings(
                gradeySession: gradeySession
            )
            linkedAccountRepository.replaceLocalAccounts(snapshot.linkedAccounts)
            notificationSettingsStore.preferences = snapshot.notificationPreferences

            let activeSchools = snapshot.linkedAccounts.filter {
                $0.provider.isSchoolProvider && $0.status == .active
            }
            let selectedAccount = snapshot.activeSchoolAccountID.flatMap { activeID in
                activeSchools.first(where: { $0.id == activeID })
            } ?? (activeSchools.count == 1 ? activeSchools[0] : nil)

            guard let selectedAccount else { return false }
            let activation = try await linkedAccountRepository.activateSchoolAccount(
                id: selectedAccount.id
            )
            _ = try repository.activateLinkedSchoolAccount(activation)
            return true
        } catch {
            return false
        }
    }
}
