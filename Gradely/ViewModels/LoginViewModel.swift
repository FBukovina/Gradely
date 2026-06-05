import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var schoolURL = ""
    var schoolSearchText = ""
    var username = ""
    var password = ""
    var isPasswordVisible = false
    var isLoading = false
    var isSchoolDirectoryLoading = false
    var isSchoolSearchActive = false
    var errorMessage: String?
    var schoolLookupErrorMessage: String?
    var directorySchools: [SchoolDirectorySchool] = []
    var selectedSchoolID: String?

    private let repository: BakalariRepository
    private let schoolDirectoryProvider: any SchoolDirectoryProviding
    private var hasLoadedSchoolDirectory = false

    init(
        repository: BakalariRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding
    ) {
        self.repository = repository
        self.schoolDirectoryProvider = schoolDirectoryProvider
    }

    var schoolSearchResults: [SchoolDirectorySchool] {
        guard isSchoolSearchActive else { return [] }
        return SchoolDirectorySearch.results(for: schoolSearchText, in: directorySchools)
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
        schoolSearchText = ""
        selectedSchoolID = nil
        isSchoolSearchActive = false
        username = DemoAccount.username
        password = DemoAccount.password
        errorMessage = nil
    }

    func loadSchoolDirectoryIfNeeded() async {
        guard !hasLoadedSchoolDirectory else { return }
        hasLoadedSchoolDirectory = true
        schoolLookupErrorMessage = nil

        let cachedDirectory = try? schoolDirectoryProvider.loadCachedDirectory()
        if let cachedDirectory {
            directorySchools = cachedDirectory.schools
        }

        let shouldRefresh = cachedDirectory?.isStale() ?? true
        guard shouldRefresh else { return }

        isSchoolDirectoryLoading = directorySchools.isEmpty
        defer { isSchoolDirectoryLoading = false }

        do {
            directorySchools = try await schoolDirectoryProvider.refreshDirectory()
            schoolLookupErrorMessage = nil
        } catch {
            if directorySchools.isEmpty {
                schoolLookupErrorMessage = String(localized: "schoolDirectory.error")
            }
        }
    }

    func updateSchoolSearch(_ text: String) {
        schoolSearchText = text
        selectedSchoolID = nil
        isSchoolSearchActive = true
    }

    func selectSchool(_ school: SchoolDirectorySchool) {
        schoolSearchText = school.trimmedName
        selectedSchoolID = school.id
        schoolURL = school.trimmedSchoolURL
        isSchoolSearchActive = false
        errorMessage = nil
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
