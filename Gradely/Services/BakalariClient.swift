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
