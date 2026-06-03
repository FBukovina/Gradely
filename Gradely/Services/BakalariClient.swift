import Foundation

protocol BakalariClient {
    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse
    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse
    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse
    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse
    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse
}

enum BakalariAPIError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return String(localized: "error.api.invalidResponse")
            case .httpStatus(let status, let message):
                if let message, !message.isEmpty {
                    return message
                }
                return String(format: String(localized: "error.api.status"), status)
            case .decoding(let message):
                return String(format: String(localized: "error.api.decoding"), message)
            }
        }
}

final class URLSessionBakalariClient: BakalariClient {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        decoder = JSONDecoder()
    }

    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse {
        try await postForm(
            baseURL: baseURL,
            path: "api/login",
            fields: [
                "client_id": "ANDR",
                "grant_type": "password",
                "username": username,
                "password": password
            ]
        )
    }

    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse {
        try await postForm(
            baseURL: baseURL,
            path: "api/login",
            fields: [
                "client_id": "ANDR",
                "grant_type": "refresh_token",
                "refresh_token": refreshToken
            ]
        )
    }

    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse {
        try await get(baseURL: baseURL, path: "api/3/marks", accessToken: accessToken)
    }

    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse {
        try await get(baseURL: baseURL, path: "api/3/absence/student", accessToken: accessToken)
    }

    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse {
        try await get(baseURL: baseURL, path: "api/3/user", accessToken: accessToken)
    }

    private func postForm<Response: Decodable>(
        baseURL: URL,
        path: String,
        fields: [String: String]
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = percentEncodedForm(fields).data(using: .utf8)
        return try await send(request)
    }

    private func get<Response: Decodable>(
        baseURL: URL,
        path: String,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BakalariAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BakalariAPIError.httpStatus(httpResponse.statusCode, readableError(from: data))
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw BakalariAPIError.decoding(error.localizedDescription)
        }
    }

    private func percentEncodedForm(_ fields: [String: String]) -> String {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery ?? ""
    }

    private func readableError(from data: Data) -> String? {
        if let loginError = try? decoder.decode(LoginErrorResponse.self, from: data) {
            return loginError.errorDescription ?? loginError.error
        }
        return String(data: data, encoding: .utf8)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}

private struct LoginErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum DemoAccount {
    static let schoolURL = "demo.gradely.app"
    static let username = "apple-review"
    static let password = "GradelyDemo2026!"

    static let accessToken = "demo-access"
    static let refreshToken = "demo-refresh"

    private static let acceptedHosts = [
        "demo",
        schoolURL
    ]

    static let loginResponse = LoginResponse(
        accessToken: accessToken,
        refreshToken: refreshToken,
        tokenType: "Bearer",
        expiresIn: 86_400,
        apiVersion: nil,
        appVersion: nil,
        userID: "demo-user"
    )

    static func isDemoBaseURL(_ baseURL: URL) -> Bool {
        guard let host = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)?
            .host?
            .lowercased()
        else {
            return false
        }

        return acceptedHosts.contains(host)
    }

    static func matches(baseURL: URL, username: String, password: String) -> Bool {
        isDemoBaseURL(baseURL)
            && username.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(Self.username) == .orderedSame
            && password == Self.password
    }

    static func isDemoToken(_ token: String) -> Bool {
        token == accessToken || token == refreshToken
    }
}

enum DemoAccountError: LocalizedError, Equatable {
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return String(localized: "error.demo.invalidCredentials")
        }
    }
}

struct MockBakalariClient: BakalariClient {
    var loginResult: LoginResponse
    var refreshedResult: LoginResponse?
    var marksResult: MarksResponse
    var absenceResult: AbsenceResponse
    var userResult: UserResponse?
    var loginError: Error?
    var marksError: Error?

    init(
        loginResult: LoginResponse = LoginResponse(
            accessToken: "mock-access",
            refreshToken: "mock-refresh",
            tokenType: "Bearer",
            expiresIn: 3600,
            apiVersion: nil,
            appVersion: nil,
            userID: "mock-user"
        ),
        refreshedResult: LoginResponse? = nil,
        marksResult: MarksResponse = PreviewData.marksResponse,
        absenceResult: AbsenceResponse = PreviewData.absenceResponse,
        userResult: UserResponse? = PreviewData.userResponse,
        loginError: Error? = nil,
        marksError: Error? = nil
    ) {
        self.loginResult = loginResult
        self.refreshedResult = refreshedResult
        self.marksResult = marksResult
        self.absenceResult = absenceResult
        self.userResult = userResult
        self.loginError = loginError
        self.marksError = marksError
    }

    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse {
        if let loginError { throw loginError }
        return loginResult
    }

    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse {
        refreshedResult ?? loginResult
    }

    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse {
        if let marksError { throw marksError }
        return marksResult
    }

    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse {
        absenceResult
    }

    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse {
        if let userResult {
            return userResult
        }
        throw BakalariAPIError.httpStatus(404, nil)
    }
}

struct DemoAwareBakalariClient: BakalariClient {
    private let liveClient: any BakalariClient
    private let demoClient: any BakalariClient

    init(
        liveClient: any BakalariClient,
        demoClient: any BakalariClient = MockBakalariClient(
            loginResult: DemoAccount.loginResponse,
            refreshedResult: DemoAccount.loginResponse
        )
    ) {
        self.liveClient = liveClient
        self.demoClient = demoClient
    }

    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse {
        guard DemoAccount.isDemoBaseURL(baseURL) else {
            return try await liveClient.login(baseURL: baseURL, username: username, password: password)
        }

        guard DemoAccount.matches(baseURL: baseURL, username: username, password: password) else {
            throw DemoAccountError.invalidCredentials
        }

        return try await demoClient.login(baseURL: baseURL, username: username, password: password)
    }

    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse {
        if DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(refreshToken) {
            return try await demoClient.refreshToken(baseURL: baseURL, refreshToken: refreshToken)
        }

        return try await liveClient.refreshToken(baseURL: baseURL, refreshToken: refreshToken)
    }

    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse {
        if DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken) {
            return try await demoClient.fetchMarks(baseURL: baseURL, accessToken: accessToken)
        }

        return try await liveClient.fetchMarks(baseURL: baseURL, accessToken: accessToken)
    }

    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse {
        if DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken) {
            return try await demoClient.fetchAbsences(baseURL: baseURL, accessToken: accessToken)
        }

        return try await liveClient.fetchAbsences(baseURL: baseURL, accessToken: accessToken)
    }

    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse {
        if DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken) {
            return try await demoClient.fetchUser(baseURL: baseURL, accessToken: accessToken)
        }

        return try await liveClient.fetchUser(baseURL: baseURL, accessToken: accessToken)
    }
}
