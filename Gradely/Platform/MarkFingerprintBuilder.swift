import CryptoKit
import Foundation

enum MarkFingerprintBuilder {
    static func fingerprint(
        for mark: Mark,
        subject: Subject,
        provider: LinkedAccountProvider,
        linkedAccountID: String
    ) -> MarkFingerprint {
        let subjectID = stableSubjectID(mark: mark, subject: subject)
        let providerMarkID = trimmed(mark.id)

        if let providerMarkID {
            let value = [
                provider.rawValue,
                linkedAccountID,
                subjectID,
                "provider",
                providerMarkID
            ].joined(separator: ":")

            return MarkFingerprint(
                provider: provider,
                linkedAccountID: linkedAccountID,
                subjectID: subjectID,
                providerMarkID: providerMarkID,
                value: value,
                source: .providerID
            )
        }

        let content = [
            provider.rawValue,
            linkedAccountID,
            subjectID,
            normalized(mark.markDate),
            normalized(mark.editDate),
            normalized(mark.markText),
            normalized(mark.caption),
            normalized(mark.theme),
            normalized(mark.type),
            normalized(mark.typeNote),
            mark.weight.map { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "",
            mark.isPoints ? "points" : "grade",
            normalized(mark.pointsText),
            mark.maxPoints.map(String.init) ?? ""
        ].joined(separator: "\u{1F}")

        let value = [
            provider.rawValue,
            linkedAccountID,
            subjectID,
            "content",
            sha256Hex(content)
        ].joined(separator: ":")

        return MarkFingerprint(
            provider: provider,
            linkedAccountID: linkedAccountID,
            subjectID: subjectID,
            providerMarkID: nil,
            value: value,
            source: .contentHash
        )
    }

    private static func stableSubjectID(mark: Mark, subject: Subject) -> String {
        trimmed(mark.subjectID) ?? trimmed(subject.id) ?? trimmed(subject.trimmedAbbrev) ?? "unknown-subject"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalized(_ value: String?) -> String {
        trimmed(value)?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ")) ?? ""
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum NewMarkNotificationFormatter {
    static func title(for event: NewMarkEvent) -> String {
        "New mark"
    }

    static func body(for event: NewMarkEvent, preferences: NotificationPreferences) -> String {
        switch preferences.lockScreenDetail {
        case .privateSummary:
            return "Open Gradey to view it"
        case .markAndSubject:
            return "\(event.markText) from \(subjectLabel(for: event))"
        case .fullDetails:
            return "\(event.markText) from \(subjectLabel(for: event))"
        }
    }

    private static func subjectLabel(for event: NewMarkEvent) -> String {
        if let abbrev = event.subjectAbbrev?.trimmingCharacters(in: .whitespacesAndNewlines), !abbrev.isEmpty {
            return abbrev
        }
        if let name = event.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "school"
    }
}

enum ProviderSecretSanitizer {
    struct SchoolPayload: Codable, Equatable {
        let provider: LinkedAccountProvider
        let baseURL: URL
        let accessToken: String
        let refreshToken: String?
        let tokenType: String
        let expiresAt: Date?
        let eduPage: EduPagePayload?
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
