import Foundation

enum GradeyAuthError: LocalizedError, Equatable {
    case notConfigured
    case missingIdentityToken
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return AppL10n.string("gradey.auth.error.notConfigured")
        case .missingIdentityToken:
            return AppL10n.string("gradey.auth.error.missingIdentityToken")
        case .server(let message):
            return message
        }
    }
}

struct SupabaseConfiguration: Equatable {
    let url: URL
    let anonKey: String

    var isConfigured: Bool {
        !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfiguration? {
        guard
            let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let anonKey = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String
        else {
            return nil
        }

        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnonKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedURL.isEmpty,
            !trimmedAnonKey.isEmpty,
            !trimmedURL.contains("$("),
            !trimmedAnonKey.contains("$("),
            let url = URL(string: trimmedURL)
        else {
            return nil
        }

        return SupabaseConfiguration(url: url, anonKey: trimmedAnonKey)
    }
}

protocol GradeyAuthSessionStoring {
    func loadSession() throws -> GradeyAuthSession?
    func save(session: GradeyAuthSession) throws
    func clearSession() throws
}

final class GradeyAuthSessionStore: GradeyAuthSessionStoring {
    private let keychain: KeychainClient
    private let sessionAccount = "gradey.id.session"

    init(keychain: KeychainClient = .live()) {
        self.keychain = keychain
    }

    func loadSession() throws -> GradeyAuthSession? {
        guard let data = try keychain.read(account: sessionAccount) else { return nil }
        return try JSONDecoder.sessionDecoder.decode(GradeyAuthSession.self, from: data)
    }

    func save(session: GradeyAuthSession) throws {
        let data = try JSONEncoder.sessionEncoder.encode(session)
        try keychain.save(data, account: sessionAccount)
    }

    func clearSession() throws {
        try keychain.delete(account: sessionAccount)
    }
}

protocol GradeyAuthClient {
    func bootstrapSession() throws -> GradeyAuthSession?
    func validSession() async throws -> GradeyAuthSession
    func refreshAccount() async throws -> GradeyAccount
    func updateFullName(_ fullName: String) async throws -> GradeyAccount
    func signInWithApple(identityToken: String, nonce: String?, fullName: String?) async throws -> GradeyAuthSession
    func signOut() async
}

final class SupabaseGradeyAuthClient: GradeyAuthClient {
    private let configuration: SupabaseConfiguration?
    private let sessionStore: any GradeyAuthSessionStoring
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dateProvider: () -> Date
    private let refreshLock = NSLock()
    private var refreshTask: Task<GradeyAuthSession, Error>?

    init(
        configuration: SupabaseConfiguration? = .fromBundle(),
        sessionStore: any GradeyAuthSessionStoring = GradeyAuthSessionStore(),
        urlSession: URLSession = .shared,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.sessionStore = sessionStore
        self.urlSession = urlSession
        self.dateProvider = dateProvider
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func bootstrapSession() throws -> GradeyAuthSession? {
        try sessionStore.loadSession()
    }

    func validSession() async throws -> GradeyAuthSession {
        guard let session = try sessionStore.loadSession() else {
            throw AppError.notLoggedIn
        }
        guard needsRefresh(session) else { return session }

        let task = sharedRefreshTask()
        defer { clearRefreshTask() }
        return try await task.value
    }

    func refreshAccount() async throws -> GradeyAccount {
        let session = try await validSession()
        let response: SupabaseUserResponse = try await send(
            path: "auth/v1/user",
            method: "GET",
            authorization: session.authorizationHeader,
            body: Optional<EmptyBody>.none
        )
        return try persistAccount(from: response, preserving: session)
    }

    func updateFullName(_ fullName: String) async throws -> GradeyAccount {
        let session = try await validSession()
        let response: SupabaseUserResponse = try await send(
            path: "auth/v1/user",
            method: "PUT",
            authorization: session.authorizationHeader,
            body: UpdateUserRequest(
                data: UpdateUserMetadata(fullName: fullName)
            )
        )
        return try persistAccount(from: response, preserving: session)
    }

    func signInWithApple(identityToken: String, nonce: String?, fullName: String?) async throws -> GradeyAuthSession {
        guard !identityToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GradeyAuthError.missingIdentityToken
        }

        cancelRefreshTask()
        let response: SupabaseTokenResponse = try await send(
            path: "auth/v1/token",
            query: ["grant_type": "id_token"],
            method: "POST",
            body: SignInWithIDTokenRequest(provider: "apple", idToken: identityToken, nonce: nonce)
        )
        var session = response.makeSession(now: dateProvider())
        let normalizedFullName = fullName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedFullName, !normalizedFullName.isEmpty {
            session.account.fullName = normalizedFullName
        }
        try sessionStore.save(session: session)

        // Apple only supplies a name on the first authorization. Keep the
        // successful auth session even if the follow-up metadata write fails.
        if let normalizedFullName, !normalizedFullName.isEmpty {
            _ = try? await updateFullName(normalizedFullName)
        }
        return (try? sessionStore.loadSession()) ?? session
    }

    func signOut() async {
        cancelRefreshTask()
        if let session = try? sessionStore.loadSession() {
            try? await sendEmpty(
                path: "auth/v1/logout",
                method: "POST",
                authorization: session.authorizationHeader,
                body: Optional<EmptyBody>.none
            )
        }
        try? sessionStore.clearSession()
    }

    private func needsRefresh(_ session: GradeyAuthSession) -> Bool {
        guard let expiresAt = session.expiresAt else { return false }
        return expiresAt <= dateProvider().addingTimeInterval(60)
    }

    private func sharedRefreshTask() -> Task<GradeyAuthSession, Error> {
        refreshLock.lock()
        defer { refreshLock.unlock() }
        if let refreshTask { return refreshTask }

        let task = Task { try await self.performRefresh() }
        refreshTask = task
        return task
    }

    private func clearRefreshTask() {
        refreshLock.lock()
        refreshTask = nil
        refreshLock.unlock()
    }

    private func cancelRefreshTask() {
        refreshLock.lock()
        let task = refreshTask
        refreshTask = nil
        refreshLock.unlock()
        task?.cancel()
    }

    private func performRefresh() async throws -> GradeyAuthSession {
        guard let current = try sessionStore.loadSession() else {
            throw AppError.notLoggedIn
        }
        guard needsRefresh(current) else { return current }
        guard let refreshToken = current.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refreshToken.isEmpty
        else {
            throw GradeyAuthError.server("Your Gradey ID session has expired. Sign in again.")
        }

        let response: SupabaseTokenResponse = try await send(
            path: "auth/v1/token",
            query: ["grant_type": "refresh_token"],
            method: "POST",
            body: RefreshTokenRequest(refreshToken: refreshToken)
        )
        try Task.checkCancellation()
        let refreshed = response.makeSession(previous: current, now: dateProvider())
        try sessionStore.save(session: refreshed)
        return refreshed
    }

    private func persistAccount(
        from response: SupabaseUserResponse,
        preserving session: GradeyAuthSession
    ) throws -> GradeyAccount {
        let account = try response.merging(into: session.account)
        var updatedSession = session
        updatedSession.account = account
        try sessionStore.save(session: updatedSession)
        return account
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        query: [String: String] = [:],
        method: String,
        authorization: String? = nil,
        body: Body?
    ) async throws -> Response {
        let data = try await sendData(
            path: path,
            query: query,
            method: method,
            authorization: authorization,
            body: body
        )
        return try decoder.decode(Response.self, from: data)
    }

    private func sendEmpty<Body: Encodable>(
        path: String,
        query: [String: String] = [:],
        method: String,
        authorization: String? = nil,
        body: Body?
    ) async throws {
        _ = try await sendData(
            path: path,
            query: query,
            method: method,
            authorization: authorization,
            body: body
        )
    }

    private func sendData<Body: Encodable>(
        path: String,
        query: [String: String] = [:],
        method: String,
        authorization: String? = nil,
        body: Body?
    ) async throws -> Data {
        guard let configuration, configuration.isConfigured else {
            throw GradeyAuthError.notConfigured
        }

        var url = configuration.url.appending(path: path)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = components.url ?? url
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(authorization ?? "Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GradeyAuthError.server(AppL10n.string("gradey.auth.error.invalidResponse"))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GradeyAuthError.server(Self.errorMessage(from: data, decoder: decoder) ?? AppL10n.string("gradey.auth.error.requestFailed"))
        }

        return data
    }

    private static func errorMessage(from data: Data, decoder: JSONDecoder) -> String? {
        if let error = try? decoder.decode(SupabaseErrorResponse.self, from: data) {
            return error.message ?? error.errorDescription ?? error.error
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

final class MockGradeyAuthClient: GradeyAuthClient {
    var session: GradeyAuthSession?
    var remoteAccount: GradeyAccount?
    var signInError: Error?
    var refreshAccountError: Error?
    var updateFullNameError: Error?

    init(
        session: GradeyAuthSession? = PreviewData.gradeyAuthSession,
        remoteAccount: GradeyAccount? = nil,
        signInError: Error? = nil,
        refreshAccountError: Error? = nil,
        updateFullNameError: Error? = nil
    ) {
        self.session = session
        self.remoteAccount = remoteAccount
        self.signInError = signInError
        self.refreshAccountError = refreshAccountError
        self.updateFullNameError = updateFullNameError
    }

    func bootstrapSession() throws -> GradeyAuthSession? {
        session
    }

    func validSession() async throws -> GradeyAuthSession {
        guard let session else { throw AppError.notLoggedIn }
        return session
    }

    func refreshAccount() async throws -> GradeyAccount {
        if let refreshAccountError {
            throw refreshAccountError
        }
        guard var updatedSession = session else { throw AppError.notLoggedIn }
        if let remoteAccount {
            guard remoteAccount.id == updatedSession.account.id else {
                throw GradeyAuthError.server(AppL10n.string("gradey.auth.error.invalidResponse"))
            }
            updatedSession.account = remoteAccount
            session = updatedSession
        }
        return updatedSession.account
    }

    func updateFullName(_ fullName: String) async throws -> GradeyAccount {
        if let updateFullNameError {
            throw updateFullNameError
        }
        guard var updatedSession = session else { throw AppError.notLoggedIn }
        updatedSession.account.fullName = fullName
        session = updatedSession
        remoteAccount = updatedSession.account
        return updatedSession.account
    }

    func signInWithApple(identityToken: String, nonce: String?, fullName: String?) async throws -> GradeyAuthSession {
        if let signInError {
            throw signInError
        }
        var signedIn = PreviewData.gradeyAuthSession
        if let fullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullName.isEmpty {
            signedIn.account.fullName = fullName
        }
        session = signedIn
        remoteAccount = signedIn.account
        return signedIn
    }

    func signOut() async {
        session = nil
    }
}

private struct SignInWithIDTokenRequest: Encodable {
    let provider: String
    let idToken: String
    let nonce: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case nonce
    }
}

private struct RefreshTokenRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct UpdateUserRequest: Encodable {
    let data: UpdateUserMetadata
}

private struct UpdateUserMetadata: Encodable {
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}

private struct EmptyBody: Encodable {}

private struct SupabaseTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: TimeInterval?
    let user: SupabaseUserResponse

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }

    func makeSession(previous: GradeyAuthSession? = nil, now: Date) -> GradeyAuthSession {
        let refreshedAccount = user.makeAccount()
        var account = refreshedAccount
        if account.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            account.fullName = previous?.account.fullName
        }
        return GradeyAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken ?? previous?.refreshToken,
            tokenType: tokenType ?? "Bearer",
            expiresAt: expiresIn.map { now.addingTimeInterval($0) },
            account: account
        )
    }
}

private struct SupabaseUserResponse: Decodable {
    let id: String
    let email: String?
    let userMetadata: SupabaseUserMetadata?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        // Profile fields are optional context, not part of the authentication
        // proof. A provider-specific value must not invalidate a valid token.
        email = try? container.decode(String.self, forKey: .email)
        userMetadata = try? container.decode(SupabaseUserMetadata.self, forKey: .userMetadata)

        let rawCreatedAt = try? container.decode(String.self, forKey: .createdAt)
        createdAt = rawCreatedAt.flatMap(Self.parseTimestamp)
    }

    func makeAccount() -> GradeyAccount {
        GradeyAccount(
            id: id,
            email: email,
            fullName: userMetadata?.fullName ?? userMetadata?.name,
            avatarURL: userMetadata?.avatarURL.flatMap(URL.init(string:)),
            createdAt: createdAt ?? Date()
        )
    }

    func merging(into account: GradeyAccount) throws -> GradeyAccount {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              id == account.id
        else {
            throw GradeyAuthError.server(AppL10n.string("gradey.auth.error.invalidResponse"))
        }

        var merged = account
        if let email = Self.nonEmpty(email) {
            merged.email = email
        }
        if let fullName = Self.nonEmpty(userMetadata?.fullName)
            ?? Self.nonEmpty(userMetadata?.name) {
            merged.fullName = fullName
        }
        if let avatarURL = Self.validAvatarURL(userMetadata?.avatarURL) {
            merged.avatarURL = avatarURL
        }
        if let createdAt {
            merged.createdAt = createdAt
        }
        return merged
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private static func validAvatarURL(_ value: String?) -> URL? {
        guard let rawValue = nonEmpty(value),
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            return nil
        }
        return url
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

/// Supabase metadata is an arbitrary JSON object. Decode only the display
/// fields Gradey uses so provider-specific booleans and nested objects do not
/// make an otherwise valid auth response fail.
private struct SupabaseUserMetadata: Decodable {
    let fullName: String?
    let name: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
        case avatarURL = "avatar_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fullName = try? container.decode(String.self, forKey: .fullName)
        name = try? container.decode(String.self, forKey: .name)
        avatarURL = try? container.decode(String.self, forKey: .avatarURL)
    }
}

private struct SupabaseErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case message
    }
}
