import Foundation

protocol BakalariClient {
    func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse
    func refreshToken(baseURL: URL, refreshToken: String) async throws -> LoginResponse
    func fetchMarks(baseURL: URL, accessToken: String) async throws -> MarksResponse
    func fetchAbsences(baseURL: URL, accessToken: String) async throws -> AbsenceResponse
    func fetchUser(baseURL: URL, accessToken: String) async throws -> UserResponse
    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse
    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject
}

enum BakalariAPIError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return AppL10n.string("error.api.invalidResponse")
            case .httpStatus(let status, let message):
                if let message, !message.isEmpty {
                    return message
                }
                return String(format: AppL10n.string("error.api.status"), status)
            case .decoding(let message):
                return String(format: AppL10n.string("error.api.decoding"), message)
            }
        }
}

final class URLSessionBakalariClient: BakalariClient {
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        decoder = JSONDecoder()
        encoder = JSONEncoder()
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

    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse {
        try await get(
            baseURL: baseURL,
            path: "api/3/timetable/actual",
            query: ["date": TimetableDates.apiDateString(date)],
            accessToken: accessToken
        )
    }

    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject {
        try await postJSON(
            baseURL: baseURL,
            path: "api/3/marks/what-if",
            body: WhatIfMarkRequest.payload(for: subject, predictedMarkText: markText, predictedWeight: weight),
            accessToken: accessToken
        )
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
        query: [String: String] = [:],
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: makeURL(baseURL: baseURL, path: path, query: query))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func postJSON<Body: Encodable, Response: Decodable>(
        baseURL: URL,
        path: String,
        body: Body,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    private func makeURL(baseURL: URL, path: String, query: [String: String]) -> URL {
        let url = baseURL.appending(path: path)
        guard
            !query.isEmpty,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url ?? url
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

private struct WhatIfMarkRequest: Encodable {
    let id: String?
    let markText: String
    let weight: Int?
    let maxPoints: Int
    let subjectID: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case markText = "MarkText"
        case weight = "Weight"
        case maxPoints = "MaxPoints"
        case subjectID = "SubjectId"
    }

    static func payload(for subject: Subject, predictedMarkText: String, predictedWeight: Int) -> [WhatIfMarkRequest] {
        let existingMarks = subject.marks.map { mark in
            WhatIfMarkRequest(
                id: mark.id,
                markText: mark.markText,
                weight: mark.weight.map { Int($0.rounded()) },
                maxPoints: mark.maxPoints ?? 0,
                subjectID: mark.subjectID
            )
        }

        let predictedMark = WhatIfMarkRequest(
            id: nil,
            markText: predictedMarkText,
            weight: max(1, predictedWeight),
            maxPoints: 0,
            subjectID: subject.id
        )

        return existingMarks + [predictedMark]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let id {
            try container.encode(id, forKey: .id)
        } else {
            try container.encodeNil(forKey: .id)
        }

        try container.encode(markText, forKey: .markText)

        if let weight {
            try container.encode(weight, forKey: .weight)
        } else {
            try container.encodeNil(forKey: .weight)
        }

        try container.encode(maxPoints, forKey: .maxPoints)
        try container.encode(subjectID, forKey: .subjectID)
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
            return AppL10n.string("error.demo.invalidCredentials")
        }
    }
}

struct MockBakalariClient: BakalariClient {
    var loginResult: LoginResponse
    var refreshedResult: LoginResponse?
    var marksResult: MarksResponse
    var absenceResult: AbsenceResponse
    var userResult: UserResponse?
    var timetableResult: TimetableResponse
    var loginError: Error?
    var marksError: Error?
    var timetableError: Error?
    var predictionResult: Subject?
    var predictionError: Error?

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
        timetableResult: TimetableResponse = PreviewData.timetableResponse,
        loginError: Error? = nil,
        marksError: Error? = nil,
        timetableError: Error? = nil,
        predictionResult: Subject? = nil,
        predictionError: Error? = nil
    ) {
        self.loginResult = loginResult
        self.refreshedResult = refreshedResult
        self.marksResult = marksResult
        self.absenceResult = absenceResult
        self.userResult = userResult
        self.timetableResult = timetableResult
        self.loginError = loginError
        self.marksError = marksError
        self.timetableError = timetableError
        self.predictionResult = predictionResult
        self.predictionError = predictionError
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

    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse {
        if let timetableError { throw timetableError }
        return Self.rebased(timetableResult, toWeekContaining: date)
    }

    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject {
        if let predictionError { throw predictionError }
        if let predictionResult { return predictionResult }

        guard let value = GradeMath.parseMarkValue(markText) else {
            return subject
        }

        let predictedAverage = GradeMath.theoreticalAverage(
            existingMarks: subject.marks,
            subjectAverageText: subject.averageText,
            markValue: value,
            weight: weight
        )

        return Subject(
            marks: subject.marks,
            subjectInfo: subject.subjectInfo,
            averageText: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), predictedAverage),
            temporaryMark: subject.temporaryMark,
            subjectNote: subject.subjectNote,
            temporaryMarkNote: subject.temporaryMarkNote,
            pointsOnly: subject.pointsOnly,
            markPredictionEnabled: subject.markPredictionEnabled
        )
    }

    /// Shifts the fixture's day dates onto the requested week so demo week navigation shows lessons.
    static func rebased(_ response: TimetableResponse, toWeekContaining date: Date) -> TimetableResponse {
        let monday = TimetableDates.monday(of: date)
        let days = response.days.map { day -> TimetableDayDTO in
            let offset = max(0, day.dayOfWeek - 1)
            let shifted = TimetableDates.weekCalendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            return TimetableDayDTO(
                atoms: day.atoms,
                dayOfWeek: day.dayOfWeek,
                date: TimetableDates.apiDateString(shifted),
                dayDescription: day.dayDescription,
                dayType: day.dayType
            )
        }
        return TimetableResponse(
            hours: response.hours,
            days: days,
            classes: response.classes,
            groups: response.groups,
            subjects: response.subjects,
            teachers: response.teachers,
            rooms: response.rooms,
            cycles: response.cycles
        )
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

    func fetchTimetable(baseURL: URL, accessToken: String, date: Date) async throws -> TimetableResponse {
        if DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken) {
            return try await demoClient.fetchTimetable(baseURL: baseURL, accessToken: accessToken, date: date)
        }

        return try await liveClient.fetchTimetable(baseURL: baseURL, accessToken: accessToken, date: date)
    }

    func predictSubject(baseURL: URL, accessToken: String, subject: Subject, markText: String, weight: Int) async throws -> Subject {
        if DemoAccount.isDemoBaseURL(baseURL) || DemoAccount.isDemoToken(accessToken) {
            return try await demoClient.predictSubject(
                baseURL: baseURL,
                accessToken: accessToken,
                subject: subject,
                markText: markText,
                weight: weight
            )
        }

        return try await liveClient.predictSubject(
            baseURL: baseURL,
            accessToken: accessToken,
            subject: subject,
            markText: markText,
            weight: weight
        )
    }
}
