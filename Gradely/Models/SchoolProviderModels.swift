import Foundation

enum SchoolProvider: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case bakalari
    case eduPage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bakalari: "Bakaláři"
        case .eduPage: "EduPage"
        }
    }

    var capabilities: SchoolProviderCapabilities {
        switch self {
        case .bakalari:
            SchoolProviderCapabilities(
                supportsParentProfiles: false,
                supportsTwoFactorAuthentication: false,
                supportsRemoteWhatIf: true,
                exposesAbsenceThreshold: true
            )
        case .eduPage:
            SchoolProviderCapabilities(
                supportsParentProfiles: true,
                supportsTwoFactorAuthentication: true,
                supportsRemoteWhatIf: false,
                exposesAbsenceThreshold: false
            )
        }
    }
}

struct SchoolProviderCapabilities: Equatable, Sendable {
    let supportsGrades = true
    let supportsAverages = true
    let supportsTimetable = true
    let supportsAttendance = true
    let supportsWidgets = true
    let supportsDirectWatchRefresh = true
    let supportsParentProfiles: Bool
    let supportsTwoFactorAuthentication: Bool
    let supportsRemoteWhatIf: Bool
    let exposesAbsenceThreshold: Bool
}

struct EduPageSubjectProfile: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let shortName: String
}

struct SchoolStudentProfile: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let fullName: String
    let classID: String?
    let className: String?
}

struct EduPageSessionData: Codable, Equatable, Sendable {
    var sessionID: String
    let username: String
    let password: String
    var gsecHash: String
    var userID: String
    var schoolName: String?
    var activeStudent: SchoolStudentProfile?
    var linkedStudents: [SchoolStudentProfile]
    var subjects: [EduPageSubjectProfile]
}

enum SchoolLoginStep: Equatable {
    case signedIn(StoredSession)
    case twoFactor(EduPageTwoFactorPrompt)
    case studentSelection([SchoolStudentProfile])
}

struct EduPageTwoFactorPrompt: Equatable, Sendable {
    let supportsCode: Bool
    let supportsDeviceApproval: Bool

    init(supportsCode: Bool = true, supportsDeviceApproval: Bool = true) {
        self.supportsCode = supportsCode
        self.supportsDeviceApproval = supportsDeviceApproval
    }
}

enum SchoolAuthenticationError: LocalizedError, Equatable {
    case missingFields
    case invalidSchoolURL
    case badCredentials
    case captchaRequired
    case twoFactorRequired
    case invalidTwoFactorCode
    case twoFactorNotConfirmed
    case parentHasNoLinkedStudents
    case invalidStudent
    case sessionExpired
    case unsupportedAccount
    case malformedResponse(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingFields:
            String(localized: "error.missingFields")
        case .invalidSchoolURL:
            String(localized: "edupage.error.schoolURL")
        case .badCredentials:
            String(localized: "edupage.error.credentials")
        case .captchaRequired:
            String(localized: "edupage.error.captcha")
        case .twoFactorRequired:
            String(localized: "edupage.error.twoFactorRequired")
        case .invalidTwoFactorCode:
            String(localized: "edupage.error.twoFactorCode")
        case .twoFactorNotConfirmed:
            String(localized: "edupage.error.twoFactorPending")
        case .parentHasNoLinkedStudents:
            String(localized: "edupage.error.noChildren")
        case .invalidStudent:
            String(localized: "edupage.error.invalidChild")
        case .sessionExpired:
            String(localized: "edupage.error.sessionExpired")
        case .unsupportedAccount:
            String(localized: "edupage.error.unsupportedAccount")
        case .malformedResponse:
            String(localized: "edupage.error.response")
        case .httpStatus(let status):
            String(format: String(localized: "error.api.status"), status)
        }
    }
}

enum EduPageURLNormalizer {
    static func normalizedBaseURL(from rawValue: String) throws -> URL {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SchoolAuthenticationError.invalidSchoolURL }

        if !value.contains("://") {
            if value.contains(".") {
                value = "https://\(value)"
            } else {
                value = "https://\(value).edupage.org"
            }
        }

        guard var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host == "edupage.org" || host.hasSuffix(".edupage.org")
        else {
            throw SchoolAuthenticationError.invalidSchoolURL
        }

        components.scheme = "https"
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw SchoolAuthenticationError.invalidSchoolURL
        }
        return url
    }
}
