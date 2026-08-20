import Foundation
import Security

/// Bakaláři username/password kept in the Keychain so the app can silently
/// re-authenticate when the rotating refresh-token chain is rejected
/// ("token already redeemed"), instead of forcing a manual logout/login.
struct BakalariCredentials: Codable, Equatable {
    let username: String
    let password: String
}

struct StoredSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var expiresAt: Date
    var baseURL: URL
    var provider: SchoolProvider
    var eduPage: EduPageSessionData?
    var bakalari: BakalariCredentials?
    var linkedAccountID: String?
    var linkedAccountDisplayName: String?
    var linkedAccountSchoolName: String?

    init(
        accessToken: String,
        refreshToken: String,
        tokenType: String,
        expiresAt: Date,
        baseURL: URL,
        provider: SchoolProvider = .bakalari,
        eduPage: EduPageSessionData? = nil,
        bakalari: BakalariCredentials? = nil,
        linkedAccountID: String? = nil,
        linkedAccountDisplayName: String? = nil,
        linkedAccountSchoolName: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.baseURL = baseURL
        self.provider = provider
        self.eduPage = eduPage
        self.bakalari = bakalari
        self.linkedAccountID = linkedAccountID
        self.linkedAccountDisplayName = linkedAccountDisplayName
        self.linkedAccountSchoolName = linkedAccountSchoolName
    }

    var isExpired: Bool {
        provider == .bakalari && expiresAt <= Date().addingTimeInterval(60)
    }

    var cacheScope: String {
        if let linkedAccountID = linkedAccountID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !linkedAccountID.isEmpty {
            return "linked-\(linkedAccountID)"
        }
        let host = baseURL.host?.lowercased() ?? baseURL.absoluteString.lowercased()
        let user = eduPage?.activeStudent?.id ?? eduPage?.userID ?? "default"
        return "\(provider.rawValue)-\(host)-\(user)"
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case tokenType
        case expiresAt
        case baseURL
        case provider
        case eduPage
        case bakalari
        case linkedAccountID
        case linkedAccountDisplayName
        case linkedAccountSchoolName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        provider = try container.decodeIfPresent(SchoolProvider.self, forKey: .provider) ?? .bakalari
        eduPage = try container.decodeIfPresent(EduPageSessionData.self, forKey: .eduPage)
        bakalari = try container.decodeIfPresent(BakalariCredentials.self, forKey: .bakalari)
        linkedAccountID = try container.decodeIfPresent(String.self, forKey: .linkedAccountID)
        linkedAccountDisplayName = try container.decodeIfPresent(String.self, forKey: .linkedAccountDisplayName)
        linkedAccountSchoolName = try container.decodeIfPresent(String.self, forKey: .linkedAccountSchoolName)
    }
}

protocol SessionStoring {
    func loadSession() throws -> StoredSession?
    func save(loginResponse: LoginResponse, baseURL: URL) throws -> StoredSession
    func save(refreshedResponse: LoginResponse, currentBaseURL: URL) throws -> StoredSession
    func save(session: StoredSession) throws
    func clearSession() throws
}

final class SessionStore: SessionStoring {
    private let keychain: KeychainClient
    private let userDefaults: UserDefaults
    private let baseURLKey = "bakalari.baseURL"
    private let sessionAccount = "bakalari.session"

    init(
        keychain: KeychainClient = .live(),
        userDefaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.userDefaults = userDefaults
    }

    func loadSession() throws -> StoredSession? {
        guard let data = try keychain.read(account: sessionAccount) else { return nil }
        var session = try JSONDecoder.sessionDecoder.decode(StoredSession.self, from: data)
        if let baseURLString = userDefaults.string(forKey: baseURLKey), let baseURL = URL(string: baseURLString) {
            session.baseURL = baseURL
        }
        return session
    }

    func save(loginResponse: LoginResponse, baseURL: URL) throws -> StoredSession {
        let session = StoredSession(
            accessToken: loginResponse.accessToken,
            refreshToken: loginResponse.refreshToken,
            tokenType: loginResponse.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(loginResponse.expiresIn)),
            baseURL: baseURL
        )
        try save(session)
        return session
    }

    func save(refreshedResponse: LoginResponse, currentBaseURL: URL) throws -> StoredSession {
        try save(loginResponse: refreshedResponse, baseURL: currentBaseURL)
    }

    func clearSession() throws {
        try keychain.delete(account: sessionAccount)
        userDefaults.removeObject(forKey: baseURLKey)
    }

    func save(session: StoredSession) throws {
        try save(session)
    }

    private func save(_ session: StoredSession) throws {
        let data = try JSONEncoder.sessionEncoder.encode(session)
        try keychain.save(data, account: sessionAccount)
        userDefaults.set(SchoolURLNormalizer.displayString(from: session.baseURL), forKey: baseURLKey)
    }
}

struct KeychainClient {
    enum KeychainError: LocalizedError {
        case unhandledStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandledStatus(let status):
                String(format: AppL10n.string("error.keychain.status"), status)
            }
        }
    }

    let service: String

    static func live(service: String = Bundle.main.bundleIdentifier ?? "Gradely") -> KeychainClient {
        KeychainClient(service: service)
    }

    func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandledStatus(status) }
        return item as? Data
    }

    func save(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.unhandledStatus(updateStatus) }

        query.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unhandledStatus(addStatus) }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainError.unhandledStatus(status)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

extension JSONEncoder {
    static var sessionEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var sessionDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

final class InMemorySessionStore: SessionStoring {
    private(set) var session: StoredSession?

    init(session: StoredSession? = nil) {
        self.session = session
    }

    func loadSession() throws -> StoredSession? {
        session
    }

    func save(loginResponse: LoginResponse, baseURL: URL) throws -> StoredSession {
        let saved = StoredSession(
            accessToken: loginResponse.accessToken,
            refreshToken: loginResponse.refreshToken,
            tokenType: loginResponse.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(loginResponse.expiresIn)),
            baseURL: baseURL
        )
        session = saved
        return saved
    }

    func save(refreshedResponse: LoginResponse, currentBaseURL: URL) throws -> StoredSession {
        try save(loginResponse: refreshedResponse, baseURL: currentBaseURL)
    }

    func clearSession() throws {
        session = nil
    }

    func save(session: StoredSession) throws {
        self.session = session
    }
}
