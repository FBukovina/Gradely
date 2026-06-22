import Foundation
import GradelyWatchShared

enum WatchBakalariError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding(String)
    case phoneAuthenticationRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The school server returned an invalid response."
        case .httpStatus(let status, let message):
            return message?.isEmpty == false ? message : "The school server returned status \(status)."
        case .decoding(let message):
            return "Could not read timetable data: \(message)"
        case .phoneAuthenticationRequired:
            return "Open Gradey on your iPhone to confirm the EduPage sign-in."
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
        if auth.resolvedProvider == .eduPage {
            return try await refreshEduPage(auth: auth)
        }
        if GradelyWatchDemoAccount.isDemo(auth) {
            return GradelyWatchAuth(
                baseURL: auth.baseURL,
                accessToken: GradelyWatchDemoAccount.accessToken,
                refreshToken: GradelyWatchDemoAccount.refreshToken,
                tokenType: "Bearer",
                expiresAt: Date().addingTimeInterval(86_400)
            )
        }

        // Prefer a password re-login (an independent token family) when we have
        // credentials, so the watch never redeems the refresh-token chain it
        // shares with the phone — that sharing is what causes the recurring
        // "token already redeemed" error. Fall back to the refresh token only
        // when no credentials were synced (older payloads).
        let fields: [String: String]
        if let username = auth.username, !username.isEmpty,
           let password = auth.password, !password.isEmpty {
            fields = [
                "client_id": "ANDR",
                "grant_type": "password",
                "username": username,
                "password": password
            ]
        } else {
            fields = [
                "client_id": "ANDR",
                "grant_type": "refresh_token",
                "refresh_token": auth.refreshToken
            ]
        }

        var request = URLRequest(url: auth.baseURL.appending(path: "api/login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = percentEncodedForm(fields).data(using: .utf8)

        let response: WatchLoginResponse = try await send(request)
        return GradelyWatchAuth(
            baseURL: auth.baseURL,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            tokenType: response.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            provider: .bakalari,
            username: auth.username,
            password: auth.password
        )
    }

    func fetchTimetable(auth: GradelyWatchAuth, weekContaining date: Date) async throws -> GradelyWatchTimetable {
        let weekStart = GradelyWatchTimetableDates.monday(of: date)

        if auth.resolvedProvider == .eduPage {
            let response = try await fetchEduPageTimetable(auth: auth, weekStart: weekStart)
            return WatchTimetableMapper.makeTimetable(from: response, weekStart: weekStart, cachedAt: Date(), today: date)
        }

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

private extension WatchBakalariClient {
    func refreshEduPage(auth: GradelyWatchAuth) async throws -> GradelyWatchAuth {
        guard let username = auth.username, let password = auth.password else {
            throw WatchBakalariError.phoneAuthenticationRequired
        }

        let loginPage = try await eduPageTextRequest(
            url: eduPageURL(baseURL: auth.baseURL, path: "login/", query: ["cmd": "MainLogin"]),
            method: "GET"
        )
        guard let csrf = capture(in: loginPage.text, prefix: "\"csrftoken\":\"") else {
            throw WatchBakalariError.phoneAuthenticationRequired
        }

        let response = try await eduPageTextRequest(
            url: eduPageURL(baseURL: auth.baseURL, path: "login/edubarLogin.php"),
            method: "POST",
            form: ["csrfauth": csrf, "username": username, "password": password]
        )
        if response.url.absoluteString.contains("cap=1")
            || response.url.absoluteString.contains("lerr=b43b43")
            || response.url.path.contains("twofactor") {
            throw WatchBakalariError.phoneAuthenticationRequired
        }
        if response.url.absoluteString.contains("bad=1") {
            throw WatchBakalariError.phoneAuthenticationRequired
        }

        guard let sessionID = urlSession.configuration.httpCookieStorage?.cookies(for: auth.baseURL)?
            .first(where: { $0.name == "PHPSESSID" })?.value
            ?? HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "PHPSESSID" })?.value
        else {
            throw WatchBakalariError.phoneAuthenticationRequired
        }

        if let selectedStudentID = auth.selectedStudentID {
            let switched = try await eduPageTextRequest(
                url: eduPageURL(
                    baseURL: auth.baseURL,
                    path: "login/switchchild",
                    query: ["studentid": selectedStudentID.filter(\.isNumber)]
                ),
                method: "GET",
                sessionID: sessionID
            )
            guard switched.text.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
                throw WatchBakalariError.phoneAuthenticationRequired
            }
        }

        return GradelyWatchAuth(
            baseURL: auth.baseURL,
            accessToken: sessionID,
            refreshToken: "",
            tokenType: "Cookie",
            expiresAt: Date().addingTimeInterval(6 * 60 * 60),
            provider: .eduPage,
            username: username,
            password: password,
            sessionID: sessionID,
            selectedStudentID: auth.selectedStudentID,
            gsecHash: auth.gsecHash
        )
    }

    func fetchEduPageTimetable(auth: GradelyWatchAuth, weekStart: Date) async throws -> WatchTimetableResponse {
        guard let sessionID = auth.sessionID ?? (auth.accessToken.isEmpty ? nil : auth.accessToken) else {
            throw WatchBakalariError.phoneAuthenticationRequired
        }
        let dashboard = try await eduPageTextRequest(
            url: eduPageURL(baseURL: auth.baseURL, path: "dashboard/eb.php", query: ["mode": "ttday"]),
            method: "GET",
            sessionID: sessionID
        )
        guard !dashboard.url.path.contains("login"),
              let gpid = lastDigits(after: "gpid=", in: dashboard.text)
                .flatMap(Int.init)
                .map({ String($0 + 1) })
        else {
            throw WatchBakalariError.phoneAuthenticationRequired
        }
        let gsh = capture(in: dashboard.text, prefix: "gsh=") ?? auth.gsecHash ?? ""
        guard !gsh.isEmpty else { throw WatchBakalariError.decoding("Missing EduPage timetable token") }

        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let response = try await eduPageTextRequest(
            url: eduPageURL(baseURL: auth.baseURL, path: "gcall"),
            method: "POST",
            sessionID: sessionID,
            form: [
                "gpid": gpid,
                "gsh": gsh,
                "action": "loadData",
                "user": auth.selectedStudentID ?? "",
                "changes": "{}",
                "date": GradelyWatchTimetableDates.apiDateString(weekStart),
                "dateto": GradelyWatchTimetableDates.apiDateString(weekEnd),
                "_LJSL": "4096"
            ]
        )
        guard !response.url.path.contains("login"),
              let root = firstJSONObject(in: response.text, containingKey: "dates"),
              let dates = root["dates"] as? [String: Any]
        else {
            throw WatchBakalariError.phoneAuthenticationRequired
        }
        return makeWatchTimetableResponse(dates: dates)
    }

    func eduPageTextRequest(
        url: URL,
        method: String,
        sessionID: String? = nil,
        form: [String: String]? = nil
    ) async throws -> (text: String, url: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let sessionID { request.setValue("PHPSESSID=\(sessionID)", forHTTPHeaderField: "Cookie") }
        if let form {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = percentEncodedForm(form).data(using: .utf8)
        }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WatchBakalariError.invalidResponse }
        guard (200..<400).contains(http.statusCode) else { throw WatchBakalariError.httpStatus(http.statusCode, nil) }
        return (String(decoding: data, as: UTF8.self), http.url ?? url)
    }

    func eduPageURL(baseURL: URL, path: String, query: [String: String] = [:]) -> URL {
        let url = baseURL.appending(path: path)
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url ?? url
    }

    func capture(in text: String, prefix: String) -> String? {
        guard let range = text.range(of: prefix) else { return nil }
        let suffix = text[range.upperBound...]
        let terminators: Set<Character> = prefix.hasSuffix("=") ? ["&", "\"", "'", " ", ">"] : ["\""]
        guard let end = suffix.firstIndex(where: { terminators.contains($0) }) else { return nil }
        let value = String(suffix[..<end])
        return value.isEmpty ? nil : value
    }

    func lastDigits(after marker: String, in text: String) -> String? {
        var cursor = text.startIndex
        var result: String?
        while let range = text.range(of: marker, range: cursor..<text.endIndex) {
            let suffix = text[range.upperBound...]
            let digits = String(suffix.drop(while: { $0 == "\"" }).prefix(while: \.isNumber))
            if !digits.isEmpty { result = digits }
            cursor = range.upperBound
        }
        return result
    }

    func firstJSONObject(in text: String, containingKey key: String) -> [String: Any]? {
        var cursor = text.startIndex
        while let start = text[cursor...].firstIndex(of: "{") {
            if let json = balancedJSONObject(in: text, from: start),
               json.contains("\"\(key)\""),
               let data = json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object[key] != nil {
                return object
            }
            cursor = text.index(after: start)
            if cursor >= text.endIndex { break }
        }
        return nil
    }

    func balancedJSONObject(in text: String, from start: String.Index) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let c = text[index]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
            index = text.index(after: index)
        }
        return nil
    }

    func makeWatchTimetableResponse(dates: [String: Any]) -> WatchTimetableResponse {
        var hours: [Int: WatchTimetableHour] = [:]
        var subjects: [String: WatchTimetableEntity] = [:]
        var teachers: [String: WatchTimetableEntity] = [:]
        var rooms: [String: WatchTimetableEntity] = [:]
        var days: [WatchTimetableDayDTO] = []

        for (date, rawDay) in dates.sorted(by: { $0.key < $1.key }) {
            guard let day = rawDay as? [String: Any], let plan = day["plan"] as? [[String: Any]] else { continue }
            var atoms: [WatchTimetableAtom] = []
            for lesson in plan where lesson["header"] == nil {
                let type = valueString(lesson["type"]) ?? "lesson"
                guard ["lesson", "event", "out", "absent", ""].contains(type) else { continue }
                let period = Int(valueString(lesson["uniperiod"]) ?? "") ?? 0
                guard period > 0 else { continue }
                let begin = valueString(lesson["starttime"]) ?? ""
                let end = valueString(lesson["endtime"]) ?? ""
                hours[period] = WatchTimetableHour(id: period, caption: "\(period)", beginTime: begin, endTime: end)

                let flags = lesson["flags"] as? [String: Any]
                let dp0 = flags?["dp0"] as? [String: Any]
                let subjectID = valueString(lesson["subjectid"] ?? dp0?["subjectid"])
                if let subjectID {
                    let name = valueString(lesson["subjectname"] ?? dp0?["subjectname"]) ?? subjectID
                    let short = valueString(lesson["subjectshort"] ?? dp0?["subjectshort"]) ?? name
                    subjects[subjectID] = WatchTimetableEntity(id: subjectID, abbrev: short, name: name)
                }
                let teacherNames = (lesson["teachernames"] as? [Any])?.compactMap(valueString) ?? []
                let teacherID = ((lesson["teacherids"] as? [Any])?.compactMap(valueString).first) ?? teacherNames.first
                if let teacherID {
                    let name = teacherNames.first ?? teacherID
                    teachers[teacherID] = WatchTimetableEntity(id: teacherID, abbrev: name, name: name)
                }
                let roomNames = (lesson["classroomnames"] as? [Any])?.compactMap(valueString) ?? []
                let roomID = ((lesson["classroomids"] as? [Any])?.compactMap(valueString).first) ?? roomNames.first
                if let roomID {
                    let name = roomNames.first ?? roomID
                    rooms[roomID] = WatchTimetableEntity(id: roomID, abbrev: name, name: name)
                }
                let canceled = type == "absent" || type.isEmpty || valueString(lesson["removed"]) == "1"
                atoms.append(WatchTimetableAtom(
                    hourID: period,
                    subjectID: subjectID,
                    teacherID: teacherID,
                    roomID: roomID,
                    change: canceled ? WatchTimetableChange(changeType: "Canceled") : nil
                ))
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let parsed = formatter.date(from: date)
            let weekday = parsed.map { Calendar.current.component(.weekday, from: $0) } ?? 2
            days.append(WatchTimetableDayDTO(
                atoms: atoms,
                dayOfWeek: weekday == 1 ? 7 : weekday - 1,
                date: date,
                dayType: (weekday == 1 || weekday == 7) ? "Weekend" : "WorkDay"
            ))
        }

        return WatchTimetableResponse(
            hours: hours.values.sorted { $0.id < $1.id },
            days: days,
            subjects: Array(subjects.values),
            teachers: Array(teachers.values),
            rooms: Array(rooms.values)
        )
    }

    func valueString(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
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
