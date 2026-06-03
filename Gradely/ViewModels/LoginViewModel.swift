import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var schoolURL = ""
    var username = ""
    var password = ""
    var isPasswordVisible = false
    var isLoading = false
    var errorMessage: String?

    private let repository: BakalariRepository

    init(repository: BakalariRepository) {
        self.repository = repository
    }

    func login() async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await repository.login(
                schoolURL: schoolURL,
                username: username,
                password: password
            )
            password = ""
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func fillDemoAccount() {
        schoolURL = DemoAccount.schoolURL
        username = DemoAccount.username
        password = DemoAccount.password
        errorMessage = nil
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
