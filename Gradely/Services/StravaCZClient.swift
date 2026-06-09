import Foundation

protocol StravaCZClient {
    func login(username: String, password: String, canteenNumber: String) async throws -> StravaCZLoginResponse
    func fetchMenu(session: StravaCZStoredSession) async throws -> StravaCZMenuResponse
    func changeMealOrder(session: StravaCZStoredSession, mealID: Int, ordered: Bool) async throws -> StravaCZBalanceResponse
    func saveOrders(session: StravaCZStoredSession) async throws -> StravaCZBalanceResponse
    func cancelOrderChanges(session: StravaCZStoredSession) async throws -> StravaCZBalanceResponse
    func logout(session: StravaCZStoredSession) async throws
}

enum StravaCZAPIError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding(String)
    case authentication(String?)
    case insufficientBalance(String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "error.stravacz.invalidResponse")
        case .httpStatus(let status, let message):
            if let message, !message.isEmpty {
                return message
            }
            return String(format: String(localized: "error.stravacz.status"), status)
        case .decoding(let message):
            return String(format: String(localized: "error.stravacz.decoding"), message)
        case .authentication(let message):
            return message ?? String(localized: "error.stravacz.authentication")
        case .insufficientBalance(let message):
            return message ?? String(localized: "error.stravacz.insufficientBalance")
        }
    }
}

final class URLSessionStravaCZClient: StravaCZClient {
    private let baseURL = URL(string: "https://app.strava.cz")!
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func login(username: String, password: String, canteenNumber: String) async throws -> StravaCZLoginResponse {
        try? await initializeSession()
        let response: StravaCZLoginResponse = try await postJSON(
            endpoint: "login",
            payload: LoginPayload(
                canteenNumber: canteenNumber,
                username: username,
                password: password
            )
        )
        return response
    }

    func fetchMenu(session: StravaCZStoredSession) async throws -> StravaCZMenuResponse {
        try await postJSON(
            endpoint: "objednavky",
            payload: MenuPayload(session: session)
        )
    }

    func changeMealOrder(session: StravaCZStoredSession, mealID: Int, ordered: Bool) async throws -> StravaCZBalanceResponse {
        try await postJSON(
            endpoint: "pridejJidloS5",
            payload: ChangeMealPayload(session: session, mealID: mealID, ordered: ordered)
        )
    }

    func saveOrders(session: StravaCZStoredSession) async throws -> StravaCZBalanceResponse {
        try await postJSON(
            endpoint: "saveOrders",
            payload: SaveOrdersPayload(session: session)
        )
    }

    func cancelOrderChanges(session: StravaCZStoredSession) async throws -> StravaCZBalanceResponse {
        try await postJSON(
            endpoint: "nactiVlastnostiPA",
            payload: CancelChangesPayload(session: session)
        )
    }

    func logout(session: StravaCZStoredSession) async throws {
        try await postJSONNoResponse(
            endpoint: "logOut",
            payload: LogoutPayload(session: session)
        )
    }

    private func initializeSession() async throws {
        _ = try await urlSession.data(from: baseURL.appending(path: "en/prihlasit-se").appending(queryItems: [
            URLQueryItem(name: "jidelna", value: nil)
        ]))
    }

    private func postJSON<Payload: Encodable, Response: Decodable>(
        endpoint: String,
        payload: Payload
    ) async throws -> Response {
        var request = makeRequest(endpoint: endpoint)
        request.httpBody = try encoder.encode(payload)
        return try await send(request)
    }

    private func postJSONNoResponse<Payload: Encodable>(
        endpoint: String,
        payload: Payload
    ) async throws {
        var request = makeRequest(endpoint: endpoint)
        request.httpBody = try encoder.encode(payload)
        try await sendNoResponse(request)
    }

    private func makeRequest(endpoint: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "api").appending(path: endpoint))
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,cs;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("\(baseURL.absoluteString)/en/prihlasit-se?jidelna", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaCZAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw StravaCZAPIError.decoding(error.localizedDescription)
        }
    }

    private func sendNoResponse(_ request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaCZAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func apiError(statusCode: Int, data: Data) -> StravaCZAPIError {
        if let apiError = try? decoder.decode(StravaCZErrorResponse.self, from: data) {
            if apiError.number == 35 {
                return .insufficientBalance(apiError.message)
            }
            if statusCode == 401 || statusCode == 403 {
                return .authentication(apiError.message)
            }
            return .httpStatus(statusCode, apiError.message)
        }

        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return statusCode == 401 || statusCode == 403
            ? .authentication(message?.isEmpty == false ? message : nil)
            : .httpStatus(statusCode, message?.isEmpty == false ? message : nil)
    }

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}

private struct StravaCZErrorResponse: Decodable {
    let number: Int?
    let message: String?
}

private struct LoginPayload: Encodable {
    let canteenNumber: String
    let username: String
    let password: String
    let keepSignedIn = true
    let environment = "W"
    let language = "EN"

    enum CodingKeys: String, CodingKey {
        case canteenNumber = "cislo"
        case username = "jmeno"
        case password = "heslo"
        case keepSignedIn = "zustatPrihlasen"
        case environment
        case language = "lang"
    }
}

private struct MenuPayload: Encodable {
    let canteenNumber: String
    let sessionID: String
    let serviceURL: String
    let language = "EN"
    let balance: Double
    let condition = ""
    let ignoreCertificate = false

    init(session: StravaCZStoredSession) {
        canteenNumber = session.canteenNumber
        sessionID = session.sessionID
        serviceURL = session.serviceURL
        balance = session.balance
    }

    enum CodingKeys: String, CodingKey {
        case canteenNumber = "cislo"
        case sessionID = "sid"
        case serviceURL = "s5url"
        case language = "lang"
        case balance = "konto"
        case condition = "podminka"
        case ignoreCertificate = "ignoreCert"
    }
}

private struct ChangeMealPayload: Encodable {
    let canteenNumber: String
    let sessionID: String
    let serviceURL: String
    let mealID: String
    let count: String
    let language = "EN"
    let ignoreCertificate = "false"

    init(session: StravaCZStoredSession, mealID: Int, ordered: Bool) {
        canteenNumber = session.canteenNumber
        sessionID = session.sessionID
        serviceURL = session.serviceURL
        self.mealID = "\(mealID)"
        count = ordered ? "1" : "0"
    }

    enum CodingKeys: String, CodingKey {
        case canteenNumber = "cislo"
        case sessionID = "sid"
        case serviceURL = "url"
        case mealID = "veta"
        case count = "pocet"
        case language = "lang"
        case ignoreCertificate = "ignoreCert"
    }
}

private struct SaveOrdersPayload: Encodable {
    let canteenNumber: String
    let sessionID: String
    let serviceURL: String
    let xml: String? = nil
    let language = "EN"
    let ignoreCertificate = "false"

    init(session: StravaCZStoredSession) {
        canteenNumber = session.canteenNumber
        sessionID = session.sessionID
        serviceURL = session.serviceURL
    }

    enum CodingKeys: String, CodingKey {
        case canteenNumber = "cislo"
        case sessionID = "sid"
        case serviceURL = "url"
        case xml
        case language = "lang"
        case ignoreCertificate = "ignoreCert"
    }
}

private struct CancelChangesPayload: Encodable {
    let sessionID: String
    let serviceURL: String
    let canteenNumber: String
    let ignoreCertificate = "false"
    let language = "EN"
    let getText = true
    let checkVersion = true
    let resetTables = true
    let frontendFunction = "refreshInformations"

    init(session: StravaCZStoredSession) {
        sessionID = session.sessionID
        serviceURL = session.serviceURL
        canteenNumber = session.canteenNumber
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "sid"
        case serviceURL = "url"
        case canteenNumber = "cislo"
        case ignoreCertificate = "ignoreCert"
        case language = "lang"
        case getText
        case checkVersion
        case resetTables
        case frontendFunction
    }
}

private struct LogoutPayload: Encodable {
    let sessionID: String
    let canteenNumber: String
    let serviceURL: String
    let language = "EN"
    let ignoreCertificate = "false"

    init(session: StravaCZStoredSession) {
        sessionID = session.sessionID
        canteenNumber = session.canteenNumber
        serviceURL = session.serviceURL
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "sid"
        case canteenNumber = "cislo"
        case serviceURL = "url"
        case language = "lang"
        case ignoreCertificate = "ignoreCert"
    }
}
