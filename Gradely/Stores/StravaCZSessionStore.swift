import Foundation

protocol StravaCZSessionStoring {
    func loadSession() throws -> StravaCZStoredSession?
    func save(loginResponse: StravaCZLoginResponse) throws -> StravaCZStoredSession
    func save(_ session: StravaCZStoredSession) throws
    func clearSession() throws
}

final class StravaCZSessionStore: StravaCZSessionStoring {
    private let keychain: KeychainClient
    private let sessionAccount = "stravacz.session"

    init(keychain: KeychainClient = .live()) {
        self.keychain = keychain
    }

    func loadSession() throws -> StravaCZStoredSession? {
        guard let data = try keychain.read(account: sessionAccount) else { return nil }
        return try JSONDecoder.sessionDecoder.decode(StravaCZStoredSession.self, from: data)
    }

    func save(loginResponse: StravaCZLoginResponse) throws -> StravaCZStoredSession {
        let session = StravaCZStoredSession(
            sessionID: loginResponse.sessionID,
            serviceURL: loginResponse.serviceURL,
            canteenNumber: loginResponse.canteenNumber,
            username: loginResponse.username,
            fullName: loginResponse.user.fullName,
            email: loginResponse.user.email,
            balance: loginResponse.user.balance,
            currency: loginResponse.user.currency,
            canteenName: loginResponse.user.canteenName,
            savedAt: Date()
        )
        try save(session)
        return session
    }

    func save(_ session: StravaCZStoredSession) throws {
        let data = try JSONEncoder.sessionEncoder.encode(session)
        try keychain.save(data, account: sessionAccount)
    }

    func clearSession() throws {
        try keychain.delete(account: sessionAccount)
    }
}

final class InMemoryStravaCZSessionStore: StravaCZSessionStoring {
    private(set) var session: StravaCZStoredSession?

    init(session: StravaCZStoredSession? = nil) {
        self.session = session
    }

    func loadSession() throws -> StravaCZStoredSession? {
        session
    }

    func save(loginResponse: StravaCZLoginResponse) throws -> StravaCZStoredSession {
        let saved = StravaCZStoredSession(
            sessionID: loginResponse.sessionID,
            serviceURL: loginResponse.serviceURL,
            canteenNumber: loginResponse.canteenNumber,
            username: loginResponse.username,
            fullName: loginResponse.user.fullName,
            email: loginResponse.user.email,
            balance: loginResponse.user.balance,
            currency: loginResponse.user.currency,
            canteenName: loginResponse.user.canteenName,
            savedAt: Date()
        )
        session = saved
        return saved
    }

    func save(_ session: StravaCZStoredSession) throws {
        self.session = session
    }

    func clearSession() throws {
        session = nil
    }
}
