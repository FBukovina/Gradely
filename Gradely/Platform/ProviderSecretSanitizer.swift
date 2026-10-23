import Foundation

enum ProviderSecretSanitizer {
    struct SchoolPayload: Codable, Equatable {
        let provider: LinkedAccountProvider
        let baseURL: URL
        let accessToken: String
        let refreshToken: String?
        let tokenType: String
        let expiresAt: Date?
        let eduPage: EduPagePayload?
        /// Set only for a separate token family created on-device for polling.
        var pollingSessionEstablishedAt: Date? = nil
    }

    struct EduPagePayload: Codable, Equatable {
        let sessionID: String
        let username: String
        let gsecHash: String
        let userID: String
        let activeStudent: SchoolStudentProfile?
        let linkedStudents: [SchoolStudentProfile]
        let subjects: [EduPageSubjectProfile]
    }

    static func schoolPayload(from session: StoredSession) -> SchoolPayload {
        SchoolPayload(
            provider: LinkedAccountProvider(schoolProvider: session.provider),
            baseURL: session.baseURL,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken.isEmpty ? nil : session.refreshToken,
            tokenType: session.tokenType,
            expiresAt: session.provider == .bakalari ? session.expiresAt : nil,
            eduPage: session.eduPage.map { data in
                EduPagePayload(
                    sessionID: data.sessionID,
                    username: data.username,
                    gsecHash: data.gsecHash,
                    userID: data.userID,
                    activeStudent: data.activeStudent,
                    linkedStudents: data.linkedStudents,
                    subjects: data.subjects
                )
            }
        )
    }
}
