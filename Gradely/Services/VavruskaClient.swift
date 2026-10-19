import Foundation

protocol VavruskaClient {
    func login(password: String) async throws -> VavruskaStoredCourse
    func fetchCalendar(_ url: URL) async throws -> [VavruskaEvent]
    func fetchNoticeBoard() async throws -> VavruskaNoticeBoard
    func fetchTicketSales(path: String) async throws -> [VavruskaRawTicketSale]
    func fetchTicketLinks() async throws -> [VavruskaTicketLink]
}

enum VavruskaAPIError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case invalidPassword
    case unexpectedPage
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            AppL10n.string("error.vavruska.invalidResponse")
        case .httpStatus(let status):
            String(format: AppL10n.string("error.vavruska.status"), status)
        case .invalidPassword:
            AppL10n.string("error.vavruska.invalidPassword")
        case .unexpectedPage:
            AppL10n.string("error.vavruska.unexpectedPage")
        case .calendarUnavailable:
            AppL10n.string("error.vavruska.calendarUnavailable")
        }
    }
}

final class URLSessionVavruskaClient: VavruskaClient {
    private static let maxResponseBytes = 2 * 1024 * 1024
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private let urlSession: URLSession

    init(urlSession: URLSession? = nil) {
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 20
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    /// Logs in with the course card password in a throwaway session (its
    /// PHPSESSID never leaves memory) and keeps only the ICS/PDF links.
    func login(password: String) async throws -> VavruskaStoredCourse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        _ = try? await session.data(for: makeRequest(VavruskaLinks.schedulePage))

        var request = makeRequest(VavruskaLinks.login)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(VavruskaLinks.base.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(VavruskaLinks.schedulePage.absoluteString, forHTTPHeaderField: "Referer")
        // `cba` is the site's honeypot: it must be present and empty.
        request.httpBody = Data("heslo=\(Self.formEncode(password))&cba=".utf8)

        let html = try await text(for: request, in: session)
        switch VavruskaHTMLParser.parseLogin(html) {
        case .course(let code, let summary, let hash):
            return VavruskaStoredCourse(
                courseCode: code,
                scheduleSummary: summary,
                calendarURL: VavruskaLinks.calendarURL(hash: hash),
                pdfURL: VavruskaLinks.pdfURL(hash: hash),
                connectedAt: Date()
            )
        case .loginForm:
            throw VavruskaAPIError.invalidPassword
        case .unknown:
            throw VavruskaAPIError.unexpectedPage
        }
    }

    func fetchCalendar(_ url: URL) async throws -> [VavruskaEvent] {
        let body: String
        do {
            body = try await text(for: makeRequest(url), in: urlSession)
        } catch VavruskaAPIError.httpStatus(let status) where status == 404 || status == 410 {
            throw VavruskaAPIError.calendarUnavailable
        }
        return try VavruskaICSParser.parse(body)
    }

    func fetchNoticeBoard() async throws -> VavruskaNoticeBoard {
        VavruskaHTMLParser.parseNoticeBoard(try await text(for: makeRequest(VavruskaLinks.noticeBoard), in: urlSession))
    }

    func fetchTicketSales(path: String) async throws -> [VavruskaRawTicketSale] {
        guard let url = VavruskaLinks.page(path) else { throw VavruskaAPIError.invalidResponse }
        return VavruskaHTMLParser.parseTicketSales(try await text(for: makeRequest(url), in: urlSession))
    }

    func fetchTicketLinks() async throws -> [VavruskaTicketLink] {
        VavruskaHTMLParser.parseTicketLinks(try await text(for: makeRequest(VavruskaLinks.tickets), in: urlSession))
    }

    // MARK: - Transport

    private func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("text/html,text/calendar;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("cs-CZ,cs;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func text(for request: URLRequest, in session: URLSession) async throws -> String {
        guard let url = request.url, VavruskaLinks.isAllowedFetchURL(url) else {
            throw VavruskaAPIError.invalidResponse
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              let finalURL = httpResponse.url, VavruskaLinks.isAllowedFetchURL(finalURL)
        else {
            throw VavruskaAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw VavruskaAPIError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= Self.maxResponseBytes,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1250)
        else {
            throw VavruskaAPIError.invalidResponse
        }
        return text
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
