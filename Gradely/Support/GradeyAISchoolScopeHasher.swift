import CryptoKit
import Foundation
import Security

protocol GradeyAISchoolScopeHashing {
    func schoolScope(for session: StoredSession) -> String
}

final class GradeyAISchoolScopeHasher: GradeyAISchoolScopeHashing {
    static let saltStorageKey = "gradey.ai.schoolScopeSalt.v1"

    private let salt: Data

    init(userDefaults: UserDefaults = .standard) {
        if let savedSalt = userDefaults.data(forKey: Self.saltStorageKey), savedSalt.count >= 16 {
            salt = savedSalt
            return
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = Array(UUID().uuidString.utf8)
        }
        let generatedSalt = Data(bytes)
        userDefaults.set(generatedSalt, forKey: Self.saltStorageKey)
        salt = generatedSalt
    }

    init(salt: Data) {
        precondition(!salt.isEmpty)
        self.salt = salt
    }

    func schoolScope(for session: StoredSession) -> String {
        var input = salt
        input.append(0)
        let schoolIdentity = SchoolDataScope(session: session).rawValue
        let providerIdentity = session.provider.rawValue
        let hostIdentity = session.baseURL.host?.lowercased() ?? session.baseURL.absoluteString.lowercased()
        let studentIdentity = session.eduPage?.activeStudent?.id
            ?? session.eduPage?.userID
            ?? "default"
        input.append(contentsOf: [
            schoolIdentity,
            providerIdentity,
            hostIdentity,
            studentIdentity,
        ].joined(separator: "\u{1F}").utf8)
        let digest = SHA256.hash(data: input)
        return "school_" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
