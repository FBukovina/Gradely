import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    enum Phase: Equatable {
        case checking
        case signedOut
        case signedIn
    }

    private let repository: SchoolRepository
    private let stravaCZRepository: StravaCZRepository

    var phase: Phase = .checking

    init(repository: SchoolRepository, stravaCZRepository: StravaCZRepository) {
        self.repository = repository
        self.stravaCZRepository = stravaCZRepository
    }

    func bootstrap() async {
        do {
            phase = try repository.bootstrapSession() == nil ? .signedOut : .signedIn
        } catch {
            phase = .signedOut
        }
    }

    func markSignedIn() {
        phase = .signedIn
    }

    func signOut() async {
        await stravaCZRepository.logout()
        try? repository.logout()
        phase = .signedOut
    }
}
