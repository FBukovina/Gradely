import Foundation

protocol LinkedAccountStoring {
    func loadAccounts() throws -> [LinkedAccount]
    func saveAccounts(_ accounts: [LinkedAccount]) throws
    func clearAccounts() throws
}

final class LinkedAccountStore: LinkedAccountStoring {
    private let userDefaults: UserDefaults
    private let key = "gradey.linkedAccounts.v1"
    private let encoder = JSONEncoder.sessionEncoder
    private let decoder = JSONDecoder.sessionDecoder

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadAccounts() throws -> [LinkedAccount] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        return try decoder.decode([LinkedAccount].self, from: data)
    }

    func saveAccounts(_ accounts: [LinkedAccount]) throws {
        let data = try encoder.encode(accounts)
        userDefaults.set(data, forKey: key)
    }

    func clearAccounts() throws {
        userDefaults.removeObject(forKey: key)
    }
}

protocol LinkedAccountClient {
    func linkSchoolAccount(session: StoredSession, user: UserResponse?, gradeySession: GradeyAuthSession) async throws -> LinkedAccount
    func linkStravaCZAccount(session: StravaCZStoredSession, gradeySession: GradeyAuthSession) async throws -> LinkedAccount
    func activateSchoolAccount(id: String, gradeySession: GradeyAuthSession) async throws -> LinkedSchoolAccountActivation
    func relinkSchoolAccount(
        id: String,
        session: StoredSession,
        user: UserResponse?,
        gradeySession: GradeyAuthSession
    ) async throws -> LinkedAccount
    func updateNotificationsEnabled(
        id: String,
        enabled: Bool,
        gradeySession: GradeyAuthSession
    ) async throws -> LinkedAccount
    func unlinkAccount(id: String, gradeySession: GradeyAuthSession) async throws
}

final class LinkedAccountRepository {
    private let store: any LinkedAccountStoring
    private let client: any LinkedAccountClient
    private let authClient: any GradeyAuthClient

    init(
        store: any LinkedAccountStoring = LinkedAccountStore(),
        client: any LinkedAccountClient,
        authClient: any GradeyAuthClient
    ) {
        self.store = store
        self.client = client
        self.authClient = authClient
    }

    func loadAccounts() -> [LinkedAccount] {
        (try? store.loadAccounts()) ?? []
    }

    func linkCurrentSchoolAccount(session: StoredSession, user: UserResponse?) async throws -> LinkedAccount {
        let gradeySession = try await requireGradeySession()
        let account = try await client.linkSchoolAccount(session: session, user: user, gradeySession: gradeySession)
        try upsert(account)
        return account
    }

    func linkCurrentStravaCZAccount(session: StravaCZStoredSession) async throws -> LinkedAccount {
        let gradeySession = try await requireGradeySession()
        let account = try await client.linkStravaCZAccount(session: session, gradeySession: gradeySession)
        try upsert(account)
        return account
    }

    func activateSchoolAccount(id: String) async throws -> LinkedSchoolAccountActivation {
        let gradeySession = try await requireGradeySession()
        let activation = try await client.activateSchoolAccount(id: id, gradeySession: gradeySession)
        try upsert(activation.account)
        return activation
    }

    func reconnectSchoolAccount(
        id: String,
        session: StoredSession,
        user: UserResponse?
    ) async throws -> LinkedAccount {
        let gradeySession = try await requireGradeySession()
        let account = try await client.relinkSchoolAccount(
            id: id,
            session: session,
            user: user,
            gradeySession: gradeySession
        )
        try upsert(account)
        return account
    }

    func updateNotificationsEnabled(id: String, enabled: Bool) async throws -> LinkedAccount {
        let gradeySession = try await requireGradeySession()
        let account = try await client.updateNotificationsEnabled(
            id: id,
            enabled: enabled,
            gradeySession: gradeySession
        )
        try upsert(account)
        return account
    }

    func unlinkAccount(id: String) async throws {
        let gradeySession = try await requireGradeySession()
        try await client.unlinkAccount(id: id, gradeySession: gradeySession)
        let updated = loadAccounts().filter { $0.id != id }
        try store.saveAccounts(updated)
    }

    func replaceLocalAccounts(_ accounts: [LinkedAccount]) {
        try? store.saveAccounts(accounts)
    }

    func clearLocalAccounts() {
        try? store.clearAccounts()
    }

    private func requireGradeySession() async throws -> GradeyAuthSession {
        try await authClient.validSession()
    }

    private func upsert(_ account: LinkedAccount) throws {
        var accounts = loadAccounts()
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        accounts.sort { $0.provider.displayName < $1.provider.displayName }
        try store.saveAccounts(accounts)
    }
}

final class SupabaseLinkedAccountClient: LinkedAccountClient {
    private let configuration: SupabaseConfiguration?
    private let urlSession: URLSession
    private let encoder = JSONEncoder.sessionEncoder
    private let decoder = JSONDecoder.gradeyAPIDecoder

    init(configuration: SupabaseConfiguration? = .fromBundle(), urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func linkSchoolAccount(session: StoredSession, user: UserResponse?, gradeySession: GradeyAuthSession) async throws -> LinkedAccount {
        let sanitized = ProviderSecretSanitizer.schoolPayload(from: session)
        let request = LinkSchoolAccountRequest(
            provider: sanitized.provider,
            baseURL: sanitized.baseURL,
            displayName: user?.fullName ?? sanitized.provider.displayName,
            schoolName: user?.displaySchoolName,
            providerUserID: user?.userUID,
            tokenPayload: sanitized
        )
        return try await send(
            function: "link-school-account",
            method: "POST",
            gradeySession: gradeySession,
            body: request
        )
    }

    func linkStravaCZAccount(session: StravaCZStoredSession, gradeySession: GradeyAuthSession) async throws -> LinkedAccount {
        let request = LinkStravaCZAccountRequest(
            displayName: session.displayName,
            canteenNumber: session.canteenNumber,
            canteenName: session.canteenName,
            username: session.username,
            serviceURL: session.serviceURL,
            sessionID: session.sessionID
        )
        return try await send(
            function: "link-stravacz-account",
            method: "POST",
            gradeySession: gradeySession,
            body: request
        )
    }

    func activateSchoolAccount(id: String, gradeySession: GradeyAuthSession) async throws -> LinkedSchoolAccountActivation {
        try await send(
            function: "activate-school-account",
            method: "POST",
            gradeySession: gradeySession,
            body: ActivateSchoolAccountRequest(id: id)
        )
    }

    func relinkSchoolAccount(
        id: String,
        session: StoredSession,
        user: UserResponse?,
        gradeySession: GradeyAuthSession
    ) async throws -> LinkedAccount {
        let sanitized = ProviderSecretSanitizer.schoolPayload(from: session)
        return try await send(
            function: "relink-school-account",
            method: "POST",
            gradeySession: gradeySession,
            body: RelinkSchoolAccountRequest(
                id: id,
                provider: sanitized.provider,
                baseURL: sanitized.baseURL,
                displayName: user?.fullName ?? sanitized.provider.displayName,
                schoolName: user?.displaySchoolName,
                providerUserID: user?.userUID,
                tokenPayload: sanitized
            )
        )
    }

    func updateNotificationsEnabled(
        id: String,
        enabled: Bool,
        gradeySession: GradeyAuthSession
    ) async throws -> LinkedAccount {
        try await send(
            function: "update-linked-account-preferences",
            method: "POST",
            gradeySession: gradeySession,
            body: UpdateLinkedAccountPreferencesRequest(id: id, notificationsEnabled: enabled)
        )
    }

    func unlinkAccount(id: String, gradeySession: GradeyAuthSession) async throws {
        try await sendEmpty(
            function: "unlink-account",
            method: "POST",
            gradeySession: gradeySession,
            body: UnlinkAccountRequest(id: id)
        )
    }

    private func send<Response: Decodable, Body: Encodable>(
        function: String,
        method: String,
        gradeySession: GradeyAuthSession,
        body: Body
    ) async throws -> Response {
        let data = try await sendData(
            function: function,
            method: method,
            gradeySession: gradeySession,
            body: body
        )
        return try decoder.decode(Response.self, from: data)
    }

    private func sendEmpty<Body: Encodable>(
        function: String,
        method: String,
        gradeySession: GradeyAuthSession,
        body: Body
    ) async throws {
        _ = try await sendData(
            function: function,
            method: method,
            gradeySession: gradeySession,
            body: body
        )
    }

    private func sendData<Body: Encodable>(
        function: String,
        method: String,
        gradeySession: GradeyAuthSession,
        body: Body
    ) async throws -> Data {
        guard let configuration else {
            throw GradeyAuthError.notConfigured
        }
        var request = URLRequest(url: configuration.url.appending(path: "functions/v1/\(function)"))
        request.httpMethod = method
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(gradeySession.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GradeyAuthError.server(AppL10n.string("gradey.account.error.invalidResponse"))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GradeyAuthError.server(message?.isEmpty == false ? message! : AppL10n.string("gradey.account.error.requestFailed"))
        }
        return data
    }
}

final class MockLinkedAccountClient: LinkedAccountClient {
    private(set) var reconnectCallCount = 0
    private var schoolPayloads: [String: ProviderSecretSanitizer.SchoolPayload] = [:]
    private var accountsByID: [String: LinkedAccount] = [:]
    private let schoolLinkError: Error?
    private let stravaCZLinkError: Error?
    private let activationError: Error?
    private let reconnectError: Error?
    private let preferencesError: Error?
    private let unlinkError: Error?

    init(
        schoolLinkError: Error? = nil,
        stravaCZLinkError: Error? = nil,
        activationError: Error? = nil,
        reconnectError: Error? = nil,
        preferencesError: Error? = nil,
        unlinkError: Error? = nil
    ) {
        self.schoolLinkError = schoolLinkError
        self.stravaCZLinkError = stravaCZLinkError
        self.activationError = activationError
        self.reconnectError = reconnectError
        self.preferencesError = preferencesError
        self.unlinkError = unlinkError
    }

    func linkSchoolAccount(session: StoredSession, user: UserResponse?, gradeySession: GradeyAuthSession) async throws -> LinkedAccount {
        if let schoolLinkError { throw schoolLinkError }
        let account = LinkedAccount(
            id: session.cacheScope,
            provider: LinkedAccountProvider(schoolProvider: session.provider),
            providerUserID: user?.userUID,
            displayName: user?.fullName ?? session.provider.displayName,
            schoolName: user?.displaySchoolName,
            canteenName: nil,
            status: .active,
            notificationsEnabled: true,
            lastPolledAt: nil,
            lastSyncedAt: Date(),
            actionRequiredReason: nil
        )
        schoolPayloads[account.id] = ProviderSecretSanitizer.schoolPayload(from: session)
        accountsByID[account.id] = account
        return account
    }

    func linkStravaCZAccount(session: StravaCZStoredSession, gradeySession: GradeyAuthSession) async throws -> LinkedAccount {
        if let stravaCZLinkError { throw stravaCZLinkError }
        let account = LinkedAccount(
            id: "stravacz-\(session.canteenNumber)-\(session.username)",
            provider: .stravaCZ,
            providerUserID: session.username,
            displayName: session.displayName,
            schoolName: nil,
            canteenName: session.canteenName,
            status: .active,
            notificationsEnabled: false,
            lastPolledAt: nil,
            lastSyncedAt: Date(),
            actionRequiredReason: nil
        )
        accountsByID[account.id] = account
        return account
    }

    func unlinkAccount(id: String, gradeySession: GradeyAuthSession) async throws {
        if let unlinkError { throw unlinkError }
        accountsByID[id] = nil
        schoolPayloads[id] = nil
    }

    func activateSchoolAccount(id: String, gradeySession: GradeyAuthSession) async throws -> LinkedSchoolAccountActivation {
        if let activationError { throw activationError }
        let payload = schoolPayloads[id] ?? ProviderSecretSanitizer.schoolPayload(from: PreviewData.expiredSession)
        let account = accountsByID[id] ?? LinkedAccount(
            id: id,
            provider: payload.provider,
            providerUserID: nil,
            displayName: payload.eduPage?.activeStudent?.fullName ?? payload.provider.displayName,
            schoolName: payload.eduPage?.activeStudent?.className,
            canteenName: nil,
            status: .active,
            notificationsEnabled: true,
            lastPolledAt: nil,
            lastSyncedAt: Date(),
            actionRequiredReason: nil
        )
        return LinkedSchoolAccountActivation(account: account, tokenPayload: payload)
    }

    func relinkSchoolAccount(
        id: String,
        session: StoredSession,
        user: UserResponse?,
        gradeySession: GradeyAuthSession
    ) async throws -> LinkedAccount {
        if let reconnectError { throw reconnectError }
        reconnectCallCount += 1
        let previous = accountsByID[id]
        let account = LinkedAccount(
            id: id,
            provider: LinkedAccountProvider(schoolProvider: session.provider),
            providerUserID: user?.userUID ?? previous?.providerUserID,
            displayName: user?.fullName ?? previous?.displayName ?? session.provider.displayName,
            schoolName: user?.displaySchoolName ?? previous?.schoolName,
            canteenName: nil,
            status: .active,
            notificationsEnabled: previous?.notificationsEnabled ?? true,
            lastPolledAt: previous?.lastPolledAt,
            lastSyncedAt: Date(),
            actionRequiredReason: nil
        )
        schoolPayloads[id] = ProviderSecretSanitizer.schoolPayload(from: session)
        accountsByID[id] = account
        return account
    }

    func updateNotificationsEnabled(
        id: String,
        enabled: Bool,
        gradeySession: GradeyAuthSession
    ) async throws -> LinkedAccount {
        if let preferencesError { throw preferencesError }
        var account = accountsByID[id] ?? PreviewData.linkedSchoolAccount
        account.id = id
        account.notificationsEnabled = enabled
        accountsByID[id] = account
        return account
    }
}

private struct LinkSchoolAccountRequest: Encodable {
    let provider: LinkedAccountProvider
    let baseURL: URL
    let displayName: String
    let schoolName: String?
    let providerUserID: String?
    let tokenPayload: ProviderSecretSanitizer.SchoolPayload

    enum CodingKeys: String, CodingKey {
        case provider
        case baseURL = "base_url"
        case displayName = "display_name"
        case schoolName = "school_name"
        case providerUserID = "provider_user_id"
        case tokenPayload = "token_payload"
    }
}

private struct LinkStravaCZAccountRequest: Encodable {
    let displayName: String
    let canteenNumber: String
    let canteenName: String?
    let username: String
    let serviceURL: String
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case canteenNumber = "canteen_number"
        case canteenName = "canteen_name"
        case username
        case serviceURL = "service_url"
        case sessionID = "session_id"
    }
}

private struct RelinkSchoolAccountRequest: Encodable {
    let id: String
    let provider: LinkedAccountProvider
    let baseURL: URL
    let displayName: String
    let schoolName: String?
    let providerUserID: String?
    let tokenPayload: ProviderSecretSanitizer.SchoolPayload

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case baseURL = "base_url"
        case displayName = "display_name"
        case schoolName = "school_name"
        case providerUserID = "provider_user_id"
        case tokenPayload = "token_payload"
    }
}

private struct UpdateLinkedAccountPreferencesRequest: Encodable {
    let id: String
    let notificationsEnabled: Bool
}

private struct UnlinkAccountRequest: Encodable {
    let id: String
}

private struct ActivateSchoolAccountRequest: Encodable {
    let id: String
}
