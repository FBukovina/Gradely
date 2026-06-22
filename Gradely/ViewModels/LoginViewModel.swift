import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var provider: SchoolProvider = .bakalari
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
    var twoFactorCode = ""
    var isTwoFactorPresented = false
    var isCheckingDeviceApproval = false
    var isStudentSelectionPresented = false
    var availableStudents: [SchoolStudentProfile] = []

    private let repository: SchoolRepository
    private let schoolDirectoryProvider: any SchoolDirectoryProviding
    private var hasLoadedSchoolDirectory = false

    init(
        repository: SchoolRepository,
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
            let step = try await repository.beginLogin(
                provider: provider,
                schoolURL: schoolURL,
                username: username,
                password: password
            )
            return handle(step)
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func completeTwoFactor() async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let step = try await repository.completeEduPageTwoFactor(code: twoFactorCode)
            return handle(step)
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func checkDeviceApproval() async -> Bool {
        errorMessage = nil
        isCheckingDeviceApproval = true
        defer { isCheckingDeviceApproval = false }
        do {
            guard try await repository.isEduPageTwoFactorConfirmed() else {
                errorMessage = SchoolAuthenticationError.twoFactorNotConfirmed.errorDescription
                return false
            }
            let step = try await repository.completeApprovedEduPageTwoFactor()
            return handle(step)
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func resendDeviceApproval() async {
        do {
            try await repository.resendEduPageTwoFactorNotification()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func selectStudent(_ student: SchoolStudentProfile) async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await repository.selectEduPageStudent(student.id)
            isStudentSelectionPresented = false
            password = ""
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func changeProvider(_ provider: SchoolProvider) {
        self.provider = provider
        schoolURL = ""
        schoolSearchText = ""
        selectedSchoolID = nil
        isSchoolSearchActive = false
        errorMessage = nil
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
        guard provider == .bakalari else { return }
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

    private func handle(_ step: SchoolLoginStep) -> Bool {
        switch step {
        case .signedIn:
            password = ""
            twoFactorCode = ""
            isTwoFactorPresented = false
            isStudentSelectionPresented = false
            return true
        case .twoFactor:
            twoFactorCode = ""
            isTwoFactorPresented = true
            return false
        case .studentSelection(let students):
            availableStudents = students
            isTwoFactorPresented = false
            isStudentSelectionPresented = true
            return false
        }
    }
}
