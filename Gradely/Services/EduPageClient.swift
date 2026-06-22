import Foundation

enum EduPageLoginResult: Equatable {
    case authenticated(EduPageSessionData)
    case twoFactor(EduPageTwoFactorPrompt)
    case studentSelection([SchoolStudentProfile])
}

protocol EduPageClient: Sendable {
    func beginLogin(baseURL: URL, username: String, password: String) async throws -> EduPageLoginResult
    func completeTwoFactor(code: String) async throws -> EduPageLoginResult
    func completeApprovedTwoFactor() async throws -> EduPageLoginResult
    func isTwoFactorConfirmed() async throws -> Bool
    func resendTwoFactorNotification() async throws
    func selectStudent(_ studentID: String) async throws -> EduPageSessionData
    func switchStudent(_ studentID: String, in session: EduPageSessionData, baseURL: URL) async throws -> EduPageSessionData
    func restore(_ stored: EduPageSessionData, baseURL: URL) async throws -> EduPageSessionData
    func fetchMarks(baseURL: URL, session: EduPageSessionData) async throws -> MarksResponse
    func fetchAbsences(baseURL: URL, session: EduPageSessionData) async throws -> AbsenceResponse
    func fetchUser(baseURL: URL, session: EduPageSessionData) async throws -> UserResponse
    func fetchTimetable(baseURL: URL, session: EduPageSessionData, weekStart: Date) async throws -> TimetableResponse
}

actor URLSessionEduPageClient: EduPageClient {
    private struct PendingLogin {
        let baseURL: URL
        let username: String
        let password: String
        var authenticationEndpoint: String?
        var authenticationToken: String?
        var csrfToken: String?
        var approvedCode: String?
    }

    private let urlSession: URLSession
    private let cookieStorage: HTTPCookieStorage
    private var pendingLogin: PendingLogin?
    private var pendingSessionData: EduPageSessionData?

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let cookieStorage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: "com.bukovinafilip.Gradely.EduPage.Ephemeral"
        )
        cookieStorage.cookies?.forEach(cookieStorage.deleteCookie)
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 20
        self.cookieStorage = cookieStorage
        urlSession = URLSession(configuration: configuration)
    }

    func beginLogin(baseURL: URL, username: String, password: String) async throws -> EduPageLoginResult {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            throw SchoolAuthenticationError.missingFields
        }

        clearCookies()
        var pending = PendingLogin(
            baseURL: baseURL,
            username: trimmedUsername,
            password: password
        )

        let loginPage = try await get(baseURL: baseURL, path: "login/", query: ["cmd": "MainLogin"])
        guard let csrf = Self.firstCapture(in: loginPage.text, prefixes: ["\"csrftoken\":\"", "name=\"csrfauth\" value=\""]) else {
            throw SchoolAuthenticationError.malformedResponse("Missing login CSRF token")
        }

        let response = try await postForm(
            baseURL: baseURL,
            path: "login/edubarLogin.php",
            fields: ["csrfauth": csrf, "username": trimmedUsername, "password": password]
        )

        if response.url.absoluteString.contains("cap=1") || response.url.absoluteString.contains("lerr=b43b43") {
            throw SchoolAuthenticationError.captchaRequired
        }
        if response.url.absoluteString.contains("bad=1") {
            throw SchoolAuthenticationError.badCredentials
        }

        if response.url.path.lowercased().contains("twofactor") || response.text.contains("/login/twofactor") {
            let twoFactorPage = response.url.path.lowercased().contains("twofactor")
                ? response
                : try await get(baseURL: baseURL, path: "login/twofactor", query: ["sn": "1"])

            pending.csrfToken = Self.firstCapture(in: twoFactorPage.text, prefixes: ["csrfauth\" value=\""])
            pending.authenticationToken = Self.firstCapture(in: twoFactorPage.text, prefixes: ["au\" value=\""])
            pending.authenticationEndpoint = Self.firstCapture(in: twoFactorPage.text, prefixes: ["gu\" value=\""])
            guard pending.csrfToken != nil,
                  pending.authenticationToken != nil,
                  pending.authenticationEndpoint != nil
            else {
                throw SchoolAuthenticationError.malformedResponse("Missing two-factor fields")
            }
            pendingLogin = pending
            return .twoFactor(EduPageTwoFactorPrompt())
        }

        pendingLogin = pending
        return try await finishLogin(from: response.text)
    }

    func completeTwoFactor(code: String) async throws -> EduPageLoginResult {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SchoolAuthenticationError.invalidTwoFactorCode }
        return try await finishTwoFactor(code: trimmed)
    }

    func completeApprovedTwoFactor() async throws -> EduPageLoginResult {
        guard let code = pendingLogin?.approvedCode else {
            throw SchoolAuthenticationError.twoFactorNotConfirmed
        }
        return try await finishTwoFactor(code: code)
    }

    func isTwoFactorConfirmed() async throws -> Bool {
        guard var pending = pendingLogin else {
            throw SchoolAuthenticationError.twoFactorRequired
        }
        let response = try await postForm(
            baseURL: pending.baseURL,
            path: "login/twofactor",
            query: ["akcia": "checkIfConfirmed"],
            fields: [:]
        )
        guard let json = try? JSONSerialization.jsonObject(with: Data(response.text.utf8)) as? [String: Any] else {
            throw SchoolAuthenticationError.malformedResponse("Invalid two-factor status")
        }
        guard (json["status"] as? String) == "ok" else { return false }
        pending.approvedCode = Self.string(json["data"])
        pendingLogin = pending
        return pending.approvedCode != nil
    }

    func resendTwoFactorNotification() async throws {
        guard let pending = pendingLogin else {
            throw SchoolAuthenticationError.twoFactorRequired
        }
        let response = try await postForm(
            baseURL: pending.baseURL,
            path: "login/twofactor",
            query: ["akcia": "resendNotifs"],
            fields: [:]
        )
        guard let json = try? JSONSerialization.jsonObject(with: Data(response.text.utf8)) as? [String: Any],
              (json["status"] as? String) == "ok"
        else {
            throw SchoolAuthenticationError.malformedResponse("Could not resend two-factor notification")
        }
    }

    func selectStudent(_ studentID: String) async throws -> EduPageSessionData {
        guard var data = pendingSessionData,
              let pending = pendingLogin,
              let student = data.linkedStudents.first(where: { $0.id == studentID })
        else {
            throw SchoolAuthenticationError.invalidStudent
        }

        let response = try await get(
            baseURL: pending.baseURL,
            path: "login/switchchild",
            query: ["studentid": Self.numericID(studentID)]
        )
        guard response.text.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
            throw SchoolAuthenticationError.invalidStudent
        }

        data.activeStudent = student
        pendingSessionData = nil
        pendingLogin = nil
        return data
    }

    func switchStudent(_ studentID: String, in session: EduPageSessionData, baseURL: URL) async throws -> EduPageSessionData {
        guard let student = session.linkedStudents.first(where: { $0.id == studentID }) else {
            throw SchoolAuthenticationError.invalidStudent
        }
        let response = try await authenticatedGet(
            baseURL: baseURL,
            sessionID: session.sessionID,
            path: "login/switchchild",
            query: ["studentid": Self.numericID(studentID)]
        )
        guard response.text.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
            throw SchoolAuthenticationError.invalidStudent
        }
        var updated = session
        updated.activeStudent = student
        return updated
    }

    func restore(_ stored: EduPageSessionData, baseURL: URL) async throws -> EduPageSessionData {
        setSessionCookie(stored.sessionID, baseURL: baseURL)
        do {
            let response = try await authenticatedGet(baseURL: baseURL, sessionID: stored.sessionID, path: "user")
            var refreshed = try parseSessionData(
                html: response.text,
                username: stored.username,
                password: stored.password,
                sessionID: stored.sessionID
            )
            if let selected = stored.activeStudent {
                let switchResponse = try await authenticatedGet(
                    baseURL: baseURL,
                    sessionID: stored.sessionID,
                    path: "login/switchchild",
                    query: ["studentid": Self.numericID(selected.id)]
                )
                guard switchResponse.text.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
                    throw SchoolAuthenticationError.sessionExpired
                }
                refreshed.activeStudent = refreshed.linkedStudents.first(where: { $0.id == selected.id }) ?? selected
            }
            return refreshed
        } catch SchoolAuthenticationError.sessionExpired {
            let result = try await beginLogin(baseURL: baseURL, username: stored.username, password: stored.password)
            switch result {
            case .authenticated(let data):
                return data
            case .studentSelection:
                guard let selectedID = stored.activeStudent?.id else {
                    throw SchoolAuthenticationError.parentHasNoLinkedStudents
                }
                return try await selectStudent(selectedID)
            case .twoFactor:
                throw SchoolAuthenticationError.twoFactorRequired
            }
        }
    }

    func fetchMarks(baseURL: URL, session: EduPageSessionData) async throws -> MarksResponse {
        let response = try await authenticatedGet(
            baseURL: baseURL,
            sessionID: session.sessionID,
            path: "znamky/",
            query: ["barNoSkin": "1"]
        )
        guard let root = Self.firstJSONObject(in: response.text, containingKey: "vsetkyZnamky"),
              let rawGrades = root["vsetkyZnamky"] as? [[String: Any]]
        else {
            throw SchoolAuthenticationError.malformedResponse("Missing grade data")
        }

        let eventsRoot = root["vsetkyUdalosti"] as? [String: Any]
        let events = eventsRoot?["edupage"] as? [String: Any] ?? [:]
        let subjectIndex = Dictionary(uniqueKeysWithValues: session.subjects.map { ($0.id, $0) })
        var grouped: [String: [Mark]] = [:]

        for rawGrade in rawGrades {
            guard let eventID = Self.string(rawGrade["udalostid"]),
                  let details = events[eventID] as? [String: Any],
                  let subjectID = Self.string(details["PredmetID"]),
                  subjectID != "vsetky"
            else { continue }

            let rawValue = Self.string(rawGrade["data"]) ?? ""
            let valueParts = rawValue.components(separatedBy: " (")
            let markText = valueParts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawValue
            let comment = valueParts.count > 1
                ? valueParts.dropFirst().joined(separator: " (").trimmingCharacters(in: CharacterSet(charactersIn: ")"))
                : nil
            let gradeType = Self.string(details["p_typ_udalosti"]) ?? "1"
            let isPoints = gradeType == "2" || gradeType == "3"
            let isSupportedCzechGrade = gradeType == "1"
                && GradeMath.parseMarkValue(markText).map { (1.0...5.0).contains($0) } == true
            let rawWeight = Self.double(details["p_vaha"])
            let weight = isPoints ? nil : rawWeight.map { $0 / 20.0 }
            let maximum = gradeType == "2"
                ? Self.double(details["p_vaha"])
                : (gradeType == "3" ? Self.double(details["p_vaha_body"]) : nil)

            grouped[subjectID, default: []].append(
                Mark(
                    markDate: Self.string(rawGrade["datum"]) ?? "",
                    caption: Self.string(details["p_meno"]),
                    theme: comment,
                    markText: markText,
                    teacherID: Self.string(details["UcitelID"]),
                    type: isPoints ? "points" : (isSupportedCzechGrade ? "grade" : "unsupported"),
                    typeNote: gradeType == "3" ? "%" : nil,
                    weight: weight,
                    subjectID: subjectID,
                    isPoints: isPoints,
                    id: eventID,
                    pointsText: isPoints ? markText : nil,
                    maxPoints: maximum.map { Int($0.rounded()) }
                )
            )
        }

        let subjects: [Subject] = grouped.map { subjectID, marks in
            let profile = subjectIndex[subjectID]
            let fallbackName = profile?.name.isEmpty == false ? profile!.name : (profile?.shortName ?? subjectID)
            return Subject(
                marks: marks,
                subjectInfo: SubjectInfo(
                    id: subjectID,
                    abbrev: profile?.shortName ?? fallbackName,
                    name: fallbackName
                ),
                averageText: nil,
                pointsOnly: !marks.isEmpty && marks.allSatisfy(\.isPoints),
                markPredictionEnabled: false
            )
        }
        .sorted { (lhs: Subject, rhs: Subject) in
            lhs.trimmedName.localizedCaseInsensitiveCompare(rhs.trimmedName) == .orderedAscending
        }

        return MarksResponse(subjects: subjects)
    }

    func fetchAbsences(baseURL: URL, session: EduPageSessionData) async throws -> AbsenceResponse {
        let targetID = session.activeStudent?.id ?? session.userID
        let response = try await authenticatedGet(
            baseURL: baseURL,
            sessionID: session.sessionID,
            path: "dashboard/eb.php",
            query: ["ebuid": targetID, "mode": "attendance"]
        )
        guard let root = Self.firstJSONObject(in: response.text, containingKey: "dateStats"),
              let allStats = root["dateStats"] as? [String: Any]
        else {
            throw SchoolAuthenticationError.malformedResponse("Missing attendance statistics")
        }

        let numericID = Self.numericID(targetID)
        guard let statsByDate = (allStats[numericID] ?? allStats[targetID]) as? [String: Any] else {
            throw SchoolAuthenticationError.malformedResponse("Attendance is unavailable for this student")
        }

        let days = statsByDate.compactMap { date, rawValue -> AbsenceDay? in
            guard let stats = rawValue as? [String: Any] else { return nil }
            let absent = Self.int(stats["absent"])
            let excused = Self.int(stats["excused"])
            let unexcused = Self.int(stats["unexcused"])
            let unresolved = max(0, absent - excused - unexcused)
            let late = Self.int(stats["late"])
            let early = Self.int(stats["early"])
            let distant = Self.int(stats["distant"])
            guard absent + late + early + distant > 0 else { return nil }
            return AbsenceDay(
                date: date,
                unsolved: unresolved,
                ok: excused,
                missed: unexcused,
                late: late,
                soon: early,
                school: 0,
                distanceTeaching: distant
            )
        }
        .sorted { $0.date < $1.date }

        return AbsenceResponse(percentageThreshold: nil, absences: days, absencesPerSubject: [])
    }

    func fetchUser(baseURL: URL, session: EduPageSessionData) async throws -> UserResponse {
        let active = session.activeStudent
        let classInfo = active?.classID.map {
            ClassInfo(id: $0, abbrev: active?.className ?? $0, name: active?.className)
        }
        return UserResponse(
            userUID: active?.id ?? session.userID,
            fullName: active?.fullName ?? session.username,
            userClass: classInfo,
            schoolName: session.schoolName,
            userType: "student",
            userTypeText: "Student",
            studyYear: Calendar.current.component(.year, from: Date())
        )
    }

    func fetchTimetable(baseURL: URL, session: EduPageSessionData, weekStart: Date) async throws -> TimetableResponse {
        let dashboard = try await authenticatedGet(
            baseURL: baseURL,
            sessionID: session.sessionID,
            path: "dashboard/eb.php",
            query: ["mode": "ttday"]
        )
        let gpid = Self.lastDigits(after: "gpid=", in: dashboard.text)
            .flatMap(Int.init)
            .map { String($0 + 1) }
        let gsh = Self.firstCapture(in: dashboard.text, prefixes: ["gsh=", "gsechash=\""]) ?? session.gsecHash
        guard let gpid, !gsh.isEmpty else {
            throw SchoolAuthenticationError.malformedResponse("Missing timetable request token")
        }

        let weekEnd = TimetableDates.weekCalendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let response = try await authenticatedPostForm(
            baseURL: baseURL,
            sessionID: session.sessionID,
            path: "gcall",
            fields: [
                "gpid": gpid,
                "gsh": gsh,
                "action": "loadData",
                "user": session.activeStudent?.id ?? session.userID,
                "changes": "{}",
                "date": TimetableDates.apiDateString(weekStart),
                "dateto": TimetableDates.apiDateString(weekEnd),
                "_LJSL": "4096"
            ]
        )

        guard let root = Self.firstJSONObject(in: response.text, containingKey: "dates"),
              let rawDates = root["dates"] as? [String: Any]
        else {
            throw SchoolAuthenticationError.malformedResponse("Missing timetable dates")
        }
        return Self.makeTimetableResponse(rawDates: rawDates, subjects: session.subjects)
    }

    private func finishTwoFactor(code: String) async throws -> EduPageLoginResult {
        guard let pending = pendingLogin,
              let csrf = pending.csrfToken,
              let endpoint = pending.authenticationEndpoint,
              let token = pending.authenticationToken
        else {
            throw SchoolAuthenticationError.twoFactorRequired
        }

        let response = try await postForm(
            baseURL: pending.baseURL,
            path: "login/edubarLogin.php",
            fields: [
                "csrfauth": csrf,
                "t2fasec": code,
                "2fNoSave": "y",
                "2fform": "1",
                "gu": endpoint,
                "au": token
            ]
        )
        guard response.text.contains("window.location = gu;") || !response.url.path.contains("twofactor") else {
            throw SchoolAuthenticationError.invalidTwoFactorCode
        }
        let userPage = try await get(baseURL: pending.baseURL, path: "user")
        return try await finishLogin(from: userPage.text)
    }

    private func finishLogin(from html: String) async throws -> EduPageLoginResult {
        guard let pending = pendingLogin,
              let sessionID = currentSessionID(baseURL: pending.baseURL)
        else {
            throw SchoolAuthenticationError.malformedResponse("Missing EduPage session")
        }
        let userHTML: String
        if Self.firstJSONObject(in: html, containingKey: "userid") != nil {
            userHTML = html
        } else {
            userHTML = try await get(baseURL: pending.baseURL, path: "user").text
        }
        let data = try parseSessionData(
            html: userHTML,
            username: pending.username,
            password: pending.password,
            sessionID: sessionID
        )
        pendingSessionData = data

        if Self.isParentID(data.userID) {
            guard !data.linkedStudents.isEmpty else {
                throw SchoolAuthenticationError.parentHasNoLinkedStudents
            }
            return .studentSelection(data.linkedStudents)
        }

        pendingSessionData = nil
        pendingLogin = nil
        return .authenticated(data)
    }

    private func parseSessionData(
        html: String,
        username: String,
        password: String,
        sessionID: String
    ) throws -> EduPageSessionData {
        guard let root = Self.firstJSONObject(in: html, containingKey: "userid"),
              let userID = Self.string(root["userid"])
        else {
            if Self.looksLikeLoginPage(html) { throw SchoolAuthenticationError.sessionExpired }
            throw SchoolAuthenticationError.malformedResponse("Missing logged-in user data")
        }

        let dbi = root["dbi"] as? [String: Any] ?? [:]
        let classes = dbi["classes"] as? [String: Any] ?? [:]
        let rawStudents = dbi["students"] as? [String: Any] ?? [:]
        let rawSubjects = dbi["subjects"] as? [String: Any] ?? [:]
        let parentNumericID = Self.numericID(userID)

        let students = rawStudents.compactMap { id, value -> SchoolStudentProfile? in
            guard let student = value as? [String: Any] else { return nil }
            let isLinked: Bool
            if Self.isParentID(userID) {
                isLinked = student.contains { key, value in
                    key.lowercased().contains("parent")
                        && Self.numericID(Self.string(value) ?? "") == parentNumericID
                }
            } else {
                isLinked = Self.numericID(id) == Self.numericID(userID)
            }
            guard isLinked else { return nil }
            let firstName = Self.string(student["firstname"]) ?? ""
            let lastName = Self.string(student["lastname"]) ?? ""
            let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
            let classID = Self.string(student["classid"])
            let classData = classID.flatMap { classes[$0] as? [String: Any] }
            let className = Self.string(classData?["short"] ?? classData?["name"])
            return SchoolStudentProfile(
                id: id.hasPrefix("Student") ? id : "Student\(id)",
                fullName: fullName.isEmpty ? username : fullName,
                classID: classID,
                className: className
            )
        }
        .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }

        let activeStudent: SchoolStudentProfile?
        if Self.isParentID(userID) {
            activeStudent = nil
        } else {
            activeStudent = students.first { Self.numericID($0.id) == Self.numericID(userID) }
                ?? students.first
        }

        let subjects = rawSubjects.compactMap { id, value -> EduPageSubjectProfile? in
            guard let subject = value as? [String: Any] else { return nil }
            let name = Self.string(subject["name"]) ?? Self.string(subject["short"]) ?? id
            let shortName = Self.string(subject["short"]) ?? name
            return EduPageSubjectProfile(id: id, name: name, shortName: shortName)
        }

        let gsec = Self.firstCapture(in: html, prefixes: ["ASC.gsechash=\"", "\"gsechash\":\""])
            ?? Self.string((root["ASC"] as? [String: Any])?["gsechash"])
            ?? ""
        let schoolName = Self.recursiveString(in: root, keys: ["schoolName", "school_name", "schoolname"])

        return EduPageSessionData(
            sessionID: sessionID,
            username: username,
            password: password,
            gsecHash: gsec,
            userID: userID,
            schoolName: schoolName,
            activeStudent: activeStudent,
            linkedStudents: students,
            subjects: subjects
        )
    }

    private func authenticatedGet(
        baseURL: URL,
        sessionID: String,
        path: String,
        query: [String: String] = [:]
    ) async throws -> HTTPTextResponse {
        var request = URLRequest(url: Self.url(baseURL: baseURL, path: path, query: query))
        request.httpMethod = "GET"
        request.setValue("PHPSESSID=\(sessionID)", forHTTPHeaderField: "Cookie")
        return try await sendAuthenticated(request)
    }

    private func authenticatedPostForm(
        baseURL: URL,
        sessionID: String,
        path: String,
        fields: [String: String]
    ) async throws -> HTTPTextResponse {
        var request = URLRequest(url: Self.url(baseURL: baseURL, path: path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("PHPSESSID=\(sessionID)", forHTTPHeaderField: "Cookie")
        request.httpBody = Self.percentEncoded(fields).data(using: .utf8)
        return try await sendAuthenticated(request)
    }

    private func sendAuthenticated(_ request: URLRequest) async throws -> HTTPTextResponse {
        let response = try await send(request)
        if response.url.path.lowercased().contains("/login") || Self.looksLikeLoginPage(response.text) {
            throw SchoolAuthenticationError.sessionExpired
        }
        return response
    }

    private func get(baseURL: URL, path: String, query: [String: String] = [:]) async throws -> HTTPTextResponse {
        var request = URLRequest(url: Self.url(baseURL: baseURL, path: path, query: query))
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func postForm(
        baseURL: URL,
        path: String,
        query: [String: String] = [:],
        fields: [String: String]
    ) async throws -> HTTPTextResponse {
        var request = URLRequest(url: Self.url(baseURL: baseURL, path: path, query: query))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.percentEncoded(fields).data(using: .utf8)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> HTTPTextResponse {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SchoolAuthenticationError.malformedResponse("Invalid HTTP response")
        }
        guard (200..<400).contains(http.statusCode) else {
            throw SchoolAuthenticationError.httpStatus(http.statusCode)
        }
        return HTTPTextResponse(
            text: String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self),
            url: http.url ?? request.url!
        )
    }

    private func currentSessionID(baseURL: URL) -> String? {
        cookieStorage.cookies(for: baseURL)?.first(where: { $0.name == "PHPSESSID" })?.value
            ?? cookieStorage.cookies?.first(where: { $0.name == "PHPSESSID" })?.value
    }

    private func setSessionCookie(_ sessionID: String, baseURL: URL) {
        guard let host = baseURL.host,
              let cookie = HTTPCookie(properties: [
                .domain: host,
                .path: "/",
                .name: "PHPSESSID",
                .value: sessionID,
                .secure: "TRUE"
              ])
        else { return }
        cookieStorage.setCookie(cookie)
    }

    private func clearCookies() {
        cookieStorage.cookies?.forEach(cookieStorage.deleteCookie)
    }
}

private struct HTTPTextResponse {
    let text: String
    let url: URL
}

private extension URLSessionEduPageClient {
    static func url(baseURL: URL, path: String, query: [String: String] = [:]) -> URL {
        let url = baseURL.appending(path: path)
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url ?? url
    }

    static func percentEncoded(_ fields: [String: String]) -> String {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery ?? ""
    }

    static func firstCapture(in text: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            guard let range = text.range(of: prefix) else { continue }
            let suffix = text[range.upperBound...]
            let terminators: [Character] = prefix.hasSuffix("=") ? ["&", "\"", "'", " ", ">"] : ["\""]
            if let end = suffix.firstIndex(where: { terminators.contains($0) }) {
                let value = String(suffix[..<end])
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    static func lastDigits(after marker: String, in text: String) -> String? {
        var searchStart = text.startIndex
        var result: String?
        while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            let suffix = text[range.upperBound...]
            let digits = String(suffix.drop(while: { $0 == "\"" }).prefix(while: \.isNumber))
            if !digits.isEmpty { result = digits }
            searchStart = range.upperBound
        }
        return result
    }

    static func firstJSONObject(in text: String, containingKey key: String) -> [String: Any]? {
        var index = text.startIndex
        while index < text.endIndex {
            guard let start = text[index...].firstIndex(of: "{") else { return nil }
            if let jsonText = balancedJSONObject(in: text, from: start),
               jsonText.contains("\"\(key)\""),
               let data = jsonText.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object[key] != nil {
                return object
            }
            index = text.index(after: start)
        }
        return nil
    }

    static func balancedJSONObject(in text: String, from start: String.Index) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                if character == "\"" {
                    inString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index])
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func recursiveString(in value: Any, keys: Set<String>) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if keys.contains(key), let result = string(child), !result.isEmpty { return result }
            }
            for child in dictionary.values {
                if let result = recursiveString(in: child, keys: keys) { return result }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = recursiveString(in: child, keys: keys) { return result }
            }
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        return string(value).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    static func int(_ value: Any?) -> Int {
        Int((double(value) ?? 0).rounded())
    }

    static func numericID(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? value : digits
    }

    static func isParentID(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("rodic") || lower.contains("parent")
    }

    static func looksLikeLoginPage(_ html: String) -> Bool {
        html.contains("cmd=MainLogin") || (html.contains("name=\"username\"") && html.contains("name=\"password\""))
    }

    static func makeTimetableResponse(
        rawDates: [String: Any],
        subjects profiles: [EduPageSubjectProfile]
    ) -> TimetableResponse {
        let subjectProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        var hoursByID: [Int: TimetableHour] = [:]
        var subjectEntities: [String: TimetableEntity] = [:]
        var teacherEntities: [String: TimetableEntity] = [:]
        var roomEntities: [String: TimetableEntity] = [:]
        var days: [TimetableDayDTO] = []

        for (date, rawDay) in rawDates.sorted(by: { $0.key < $1.key }) {
            guard let day = rawDay as? [String: Any], let plan = day["plan"] as? [[String: Any]] else { continue }
            var atoms: [TimetableAtom] = []

            for lesson in plan {
                if lesson["header"] != nil { continue }
                let type = string(lesson["type"]) ?? "lesson"
                guard ["lesson", "event", "out", "absent", ""].contains(type) else { continue }

                let period = int(lesson["uniperiod"])
                guard period > 0 else { continue }
                let begin = (string(lesson["starttime"]) ?? "").replacingOccurrences(of: "24:00", with: "23:59")
                let end = (string(lesson["endtime"]) ?? "").replacingOccurrences(of: "24:00", with: "23:59")
                hoursByID[period] = TimetableHour(id: period, caption: String(period), beginTime: begin, endTime: end)

                let flags = lesson["flags"] as? [String: Any]
                let dp0 = flags?["dp0"] as? [String: Any]
                let event = flags?["event"] as? [String: Any]
                let subjectID = string(lesson["subjectid"] ?? dp0?["subjectid"])
                if let subjectID {
                    let profile = subjectProfiles[subjectID]
                    let name = profile?.name ?? string(lesson["subjectname"] ?? dp0?["subjectname"]) ?? subjectID
                    let short = profile?.shortName ?? string(lesson["subjectshort"] ?? dp0?["subjectshort"]) ?? name
                    subjectEntities[subjectID] = TimetableEntity(id: subjectID, abbrev: short, name: name)
                }

                let teacherIDs = (lesson["teacherids"] as? [Any])?.compactMap(string) ?? []
                let teacherNames = (lesson["teachernames"] as? [Any])?.compactMap(string) ?? []
                let teacherID = teacherIDs.first ?? teacherNames.first
                if let teacherID {
                    let name = teacherNames.first ?? teacherID
                    teacherEntities[teacherID] = TimetableEntity(id: teacherID, abbrev: name, name: name)
                }

                let roomIDs = (lesson["classroomids"] as? [Any])?.compactMap(string) ?? []
                let roomNames = (lesson["classroomnames"] as? [Any])?.compactMap(string) ?? []
                let roomID = roomIDs.first ?? roomNames.first
                if let roomID {
                    let name = roomNames.first ?? roomID
                    roomEntities[roomID] = TimetableEntity(id: roomID, abbrev: name, name: name)
                }

                let isCanceled = (lesson["removed"] as? Bool == true)
                    || int(lesson["removed"]) == 1
                    || type == "absent"
                    || type.isEmpty
                let change = isCanceled
                    ? TimetableChange(changeType: "Canceled", description: string(lesson["changeinfo"] ?? lesson["note"]))
                    : nil
                let theme = string(dp0?["note_wd"] ?? event?["name"] ?? lesson["curriculum"])

                atoms.append(
                    TimetableAtom(
                        hourID: period,
                        groupIDs: (lesson["groupnames"] as? [Any])?.compactMap(string) ?? [],
                        subjectID: subjectID,
                        teacherID: teacherID,
                        roomID: roomID,
                        change: change,
                        theme: theme
                    )
                )
            }

            let parsedDate = MarkDateFormatter.date(from: date)
            let weekday = parsedDate.map { TimetableDates.weekCalendar.component(.weekday, from: $0) } ?? 2
            let mondayBasedWeekday = weekday == 1 ? 7 : weekday - 1
            days.append(
                TimetableDayDTO(
                    atoms: atoms,
                    dayOfWeek: mondayBasedWeekday,
                    date: date,
                    dayType: mondayBasedWeekday <= 5 ? "WorkDay" : "Weekend"
                )
            )
        }

        return TimetableResponse(
            hours: hoursByID.values.sorted { $0.id < $1.id },
            days: days,
            subjects: Array(subjectEntities.values),
            teachers: Array(teacherEntities.values),
            rooms: Array(roomEntities.values)
        )
    }
}
