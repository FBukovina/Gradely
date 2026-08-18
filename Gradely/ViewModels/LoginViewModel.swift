import Foundation
import Observation

struct SchoolLoginPrefill: Equatable {
    let provider: SchoolProvider
    let schoolURL: String
    let schoolName: String
    let username: String

    init?(
        session: StoredSession,
        account: LinkedAccount,
        allowsUnscopedSession: Bool = false
    ) {
        guard account.provider.isSchoolProvider else { return nil }
        guard session.linkedAccountID == account.id
                || (allowsUnscopedSession && session.linkedAccountID == nil)
        else {
            return nil
        }

        let accountProvider = LinkedAccountProvider(schoolProvider: session.provider)
        guard account.provider == accountProvider else { return nil }

        let username: String
        switch session.provider {
        case .bakalari:
            username = session.bakalari?.username ?? ""
        case .eduPage:
            username = session.eduPage?.username ?? ""
        }

        self.provider = session.provider
        schoolURL = session.baseURL.absoluteString
        schoolName = account.schoolName
            ?? session.linkedAccountSchoolName
            ?? account.subtitle
        self.username = username
    }
}

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
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        prefill: SchoolLoginPrefill? = nil
    ) {
        self.repository = repository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        if let prefill {
            provider = prefill.provider
            schoolURL = prefill.schoolURL
            schoolSearchText = prefill.schoolName
            username = prefill.username
        }
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
        } else {
            directorySchools = []
        }

        let shouldRefresh = cachedDirectory.map {
            $0.isStale() || !$0.isCurrentFormat
        } ?? true
        guard shouldRefresh else { return }

        isSchoolDirectoryLoading = directorySchools.isEmpty
        defer { isSchoolDirectoryLoading = false }

        do {
            directorySchools = try await schoolDirectoryProvider.refreshDirectory()
            schoolLookupErrorMessage = nil
        } catch {
            hasLoadedSchoolDirectory = false
            if directorySchools.isEmpty {
                schoolLookupErrorMessage = String(localized: "schoolDirectory.error")
            }
        }
    }

    func retrySchoolDirectory() async {
        guard !isSchoolDirectoryLoading else { return }
        hasLoadedSchoolDirectory = false
        await loadSchoolDirectoryIfNeeded()
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
