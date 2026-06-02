import Foundation
import Security

struct StoredSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var expiresAt: Date
    var baseURL: URL

    var isExpired: Bool {
        expiresAt <= Date().addingTimeInterval(60)
    }
}

protocol SessionStoring {
    func loadSession() throws -> StoredSession?
    func save(loginResponse: LoginResponse, baseURL: URL) throws -> StoredSession
    func save(refreshedResponse: LoginResponse, currentBaseURL: URL) throws -> StoredSession
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
                String(format: String(localized: "error.keychain.status"), status)
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
}
