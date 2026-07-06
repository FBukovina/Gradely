import Foundation

enum GradeyAuthError: LocalizedError, Equatable {
    case notConfigured
    case missingIdentityToken
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "gradey.auth.error.notConfigured")
        case .missingIdentityToken:
            return String(localized: "gradey.auth.error.missingIdentityToken")
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
    func signInWithApple(identityToken: String, nonce: String?, fullName: String?) async throws -> GradeyAuthSession
    func signOut() async
}

final class SupabaseGradeyAuthClient: GradeyAuthClient {
    private let configuration: SupabaseConfiguration?
    private let sessionStore: any GradeyAuthSessionStoring
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: SupabaseConfiguration? = .fromBundle(),
        sessionStore: any GradeyAuthSessionStoring = GradeyAuthSessionStore(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.sessionStore = sessionStore
        self.urlSession = urlSession
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func bootstrapSession() throws -> GradeyAuthSession? {
        try sessionStore.loadSession()
    }

    func signInWithApple(identityToken: String, nonce: String?, fullName: String?) async throws -> GradeyAuthSession {
        guard !identityToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GradeyAuthError.missingIdentityToken
        }

        let response: SupabaseTokenResponse = try await send(
            path: "auth/v1/token",
            query: ["grant_type": "id_token"],
            method: "POST",
            body: SignInWithIDTokenRequest(provider: "apple", idToken: identityToken, nonce: nonce)
        )
        var session = response.makeSession()
        if let fullName, !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.account.fullName = fullName
        }
        try sessionStore.save(session: session)
        return session
    }

    func signOut() async {
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
            throw GradeyAuthError.server(String(localized: "gradey.auth.error.invalidResponse"))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GradeyAuthError.server(Self.errorMessage(from: data, decoder: decoder) ?? String(localized: "gradey.auth.error.requestFailed"))
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

    init(session: GradeyAuthSession? = PreviewData.gradeyAuthSession) {
        self.session = session
    }

    func bootstrapSession() throws -> GradeyAuthSession? {
        session
    }

    func signInWithApple(identityToken: String, nonce: String?, fullName: String?) async throws -> GradeyAuthSession {
        let signedIn = PreviewData.gradeyAuthSession
        session = signedIn
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

    func makeSession() -> GradeyAuthSession {
        GradeyAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType ?? "Bearer",
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            account: user.makeAccount()
        )
    }
}

private struct SupabaseUserResponse: Decodable {
    let id: String
    let email: String?
    let userMetadata: [String: String]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
        case createdAt = "created_at"
    }

    func makeAccount() -> GradeyAccount {
        GradeyAccount(
            id: id,
            email: email,
            fullName: userMetadata?["full_name"] ?? userMetadata?["name"],
            avatarURL: userMetadata?["avatar_url"].flatMap(URL.init(string:)),
            createdAt: createdAt ?? Date()
        )
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
