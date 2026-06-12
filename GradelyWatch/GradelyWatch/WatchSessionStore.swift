import Foundation
import GradelyWatchShared
import Security

final class WatchSessionStore {
    private let keychain: WatchKeychainClient
    private let account = "bakalari.session"

    init(service: String = Bundle.main.bundleIdentifier ?? "GradelyWatch") {
        keychain = WatchKeychainClient(service: service)
    }

    func load() throws -> GradelyWatchAuth? {
        guard let data = try keychain.read(account: account) else {
            return nil
        }
        return try GradelyWatchSyncCodec.decoder.decode(GradelyWatchAuth.self, from: data)
    }

    func save(_ auth: GradelyWatchAuth) throws {
        let data = try GradelyWatchSyncCodec.encoder.encode(auth)
        try keychain.save(data, account: account)
    }

    func clear() throws {
        try keychain.delete(account: account)
    }
}

struct WatchKeychainClient {
    enum KeychainError: LocalizedError, Equatable {
        case unhandledStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandledStatus(let status):
                return "Keychain error \(status)."
            }
        }
    }

    let service: String

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
