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

    private let repository: BakalariRepository

    var phase: Phase = .checking

    init(repository: BakalariRepository) {
        self.repository = repository
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

    func signOut() {
        do {
            try repository.logout()
        } catch {
            // If cleanup fails, the safest user-facing state is still signed out.
        }
        phase = .signedOut
    }
}
