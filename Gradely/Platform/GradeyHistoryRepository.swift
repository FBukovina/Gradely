import Foundation

protocol GradeyHistoryClient {
    func loadGradeHistory(
        linkedAccountID: String?,
        days: Int?,
        gradeySession: GradeyAuthSession
    ) async throws -> GradeHistoryResponse
}

final class GradeyHistoryRepository {
    private let client: any GradeyHistoryClient
    private let authClient: any GradeyAuthClient

    init(
        client: any GradeyHistoryClient,
        authClient: any GradeyAuthClient
    ) {
        self.client = client
        self.authClient = authClient
    }

    func loadGradeHistory(linkedAccountID: String?, days: Int? = 90) async throws -> GradeHistoryResponse {
        let gradeySession = try await authClient.validSession()
        return try await client.loadGradeHistory(
            linkedAccountID: linkedAccountID,
            days: days,
            gradeySession: gradeySession
        )
    }
}

final class SupabaseGradeyHistoryClient: GradeyHistoryClient {
    private let configuration: SupabaseConfiguration?
    private let urlSession: URLSession
    private let encoder = JSONEncoder.sessionEncoder
    private let decoder = JSONDecoder.sessionDecoder

    init(configuration: SupabaseConfiguration? = .fromBundle(), urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func loadGradeHistory(
        linkedAccountID: String?,
        days: Int?,
        gradeySession: GradeyAuthSession
    ) async throws -> GradeHistoryResponse {
        guard let configuration else { throw GradeyAuthError.notConfigured }
        var request = URLRequest(url: configuration.url.appending(path: "functions/v1/grade-history"))
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(gradeySession.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(GradeHistoryRequest(linkedAccountID: linkedAccountID, days: days))

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GradeyAuthError.server(String(localized: "gradey.account.error.invalidResponse"))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GradeyAuthError.server(message?.isEmpty == false ? message! : String(localized: "gradey.account.error.requestFailed"))
        }
        return try decoder.decode(GradeHistoryResponse.self, from: data)
    }
}

final class MockGradeyHistoryClient: GradeyHistoryClient {
    var response: GradeHistoryResponse
    var error: Error?

    init(response: GradeHistoryResponse = GradeHistoryResponse(events: [], recentNewMarkEvents: []), error: Error? = nil) {
        self.response = response
        self.error = error
    }

    func loadGradeHistory(
        linkedAccountID: String?,
        days: Int?,
        gradeySession: GradeyAuthSession
    ) async throws -> GradeHistoryResponse {
        if let error { throw error }
        return response
    }
}

private struct GradeHistoryRequest: Encodable {
    let linkedAccountID: String?
    let days: Int?

    enum CodingKeys: String, CodingKey {
        case linkedAccountID = "linked_account_id"
        case days
    }
}
