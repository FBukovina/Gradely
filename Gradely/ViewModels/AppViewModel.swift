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
    private let requiresGradeyID: Bool

    var phase: Phase = .checking
    var gradeyAccount: GradeyAccount?
    private(set) var bypassesGradeyIDForTesting = false

    var usesGradeyIDGate: Bool {
        #if DEBUG
        requiresGradeyID && !bypassesGradeyIDForTesting
        #else
        requiresGradeyID
        #endif
    }

    init(
        repository: SchoolRepository,
        stravaCZRepository: StravaCZRepository,
        gradeyAuthClient: any GradeyAuthClient,
        linkedAccountRepository: LinkedAccountRepository,
        requiresGradeyID: Bool
    ) {
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
        self.gradeyAuthClient = gradeyAuthClient
        self.linkedAccountRepository = linkedAccountRepository
        self.requiresGradeyID = requiresGradeyID
    }

    func bootstrap() async {
        do {
            if usesGradeyIDGate {
                guard let gradeySession = try gradeyAuthClient.bootstrapSession() else {
                    gradeyAccount = nil
                    phase = .signedOut
                    return
                }
                gradeyAccount = gradeySession.account
            }

            phase = try repository.bootstrapSession() == nil ? .signedInNeedsSchool : .signedIn
        } catch {
            phase = .signedOut
        }
    }

    func markGradeySignedIn() async {
        gradeyAccount = try? gradeyAuthClient.bootstrapSession()?.account
        await bootstrap()
    }

    func bypassGradeyIDForTesting() async {
        bypassesGradeyIDForTesting = true
        gradeyAccount = nil
        await bootstrap()
    }

    func markSignedIn() {
        phase = .signedIn
    }

    func markNeedsSchool() {
        phase = .signedInNeedsSchool
    }

    func signOut() async {
        await stravaCZRepository.logout()
        await gradeyAuthClient.signOut()
        linkedAccountRepository.clearLocalAccounts()
        try? repository.logout()
        phase = .signedOut
    }
}
