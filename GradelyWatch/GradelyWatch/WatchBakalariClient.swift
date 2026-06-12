import Foundation
import GradelyWatchShared

enum WatchBakalariError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The school server returned an invalid response."
        case .httpStatus(let status, let message):
            return message?.isEmpty == false ? message : "The school server returned status \(status)."
        case .decoding(let message):
            return "Could not read timetable data: \(message)"
        }
    }
}

final class WatchBakalariClient {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        decoder = JSONDecoder()
    }

    func refresh(auth: GradelyWatchAuth) async throws -> GradelyWatchAuth {
        if GradelyWatchDemoAccount.isDemo(auth) {
            return GradelyWatchAuth(
                baseURL: auth.baseURL,
                accessToken: GradelyWatchDemoAccount.accessToken,
                refreshToken: GradelyWatchDemoAccount.refreshToken,
                tokenType: "Bearer",
                expiresAt: Date().addingTimeInterval(86_400)
            )
        }

        var request = URLRequest(url: auth.baseURL.appending(path: "api/login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = percentEncodedForm([
            "client_id": "ANDR",
            "grant_type": "refresh_token",
            "refresh_token": auth.refreshToken
        ]).data(using: .utf8)

        let response: WatchLoginResponse = try await send(request)
        return GradelyWatchAuth(
            baseURL: auth.baseURL,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            tokenType: response.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    func fetchTimetable(auth: GradelyWatchAuth, weekContaining date: Date) async throws -> GradelyWatchTimetable {
        let weekStart = GradelyWatchTimetableDates.monday(of: date)

        if GradelyWatchDemoAccount.isDemo(auth) {
            return GradelyWatchDemoTimetable.make(weekStart: weekStart, now: date)
        }

        var request = URLRequest(url: makeTimetableURL(baseURL: auth.baseURL, date: weekStart))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(auth.tokenType) \(auth.accessToken)", forHTTPHeaderField: "Authorization")

        let response: WatchTimetableResponse = try await send(request)
        return WatchTimetableMapper.makeTimetable(from: response, weekStart: weekStart, cachedAt: Date(), today: date)
    }

    func makeTimetableURL(baseURL: URL, date: Date) -> URL {
        let url = baseURL.appending(path: "api/3/timetable/actual")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.queryItems = [
            URLQueryItem(name: "date", value: GradelyWatchTimetableDates.apiDateString(date))
        ]
        return components.url ?? url
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WatchBakalariError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WatchBakalariError.httpStatus(httpResponse.statusCode, readableError(from: data))
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw WatchBakalariError.decoding(error.localizedDescription)
        }
    }

    private func percentEncodedForm(_ fields: [String: String]) -> String {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery ?? ""
    }

    private func readableError(from data: Data) -> String? {
        if let loginError = try? decoder.decode(WatchLoginErrorResponse.self, from: data) {
            return loginError.errorDescription ?? loginError.error
        }
        return String(data: data, encoding: .utf8)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}

private struct WatchLoginResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

private struct WatchLoginErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum GradelyWatchDemoAccount {
    static let schoolURL = "demo.gradely.app"
    static let accessToken = "demo-access"
    static let refreshToken = "demo-refresh"

    static func isDemo(_ auth: GradelyWatchAuth) -> Bool {
        isDemoBaseURL(auth.baseURL) || auth.accessToken == accessToken || auth.refreshToken == refreshToken
    }

    private static func isDemoBaseURL(_ baseURL: URL) -> Bool {
        guard let host = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)?.host?.lowercased() else {
            return false
        }

        return host == "demo" || host == schoolURL
    }
}
