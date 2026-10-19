import Foundation

enum VavruskaAppError: LocalizedError, Equatable {
    case notConnected
    case missingPassword

    var errorDescription: String? {
        switch self {
        case .notConnected: AppL10n.string("error.vavruska.notConnected")
        case .missingPassword: AppL10n.string("error.missingFields")
        }
    }
}

struct VavruskaRefreshResult {
    let snapshot: VavruskaSnapshot
    /// Something could not be fetched this time; the cache is still shown.
    let failed: Bool
}

/// Fetches politely: one request at a time, each source on its own schedule,
/// so a busy user opening the app all day costs the site a handful of GETs.
final class VavruskaRepository {
    private enum Policy {
        static let calendar: TimeInterval = 6 * 60 * 60
        static let endedCalendar: TimeInterval = 7 * 24 * 60 * 60
        static let noticeBoard: TimeInterval = 6 * 60 * 60
        static let ticketSales: TimeInterval = 12 * 60 * 60
        static let ticketLinks: TimeInterval = 30 * 60
        /// Pull to refresh never refetches anything younger than this.
        static let forcedFloor: TimeInterval = 2 * 60
        static let maxEventPages = 5
    }

    private let client: any VavruskaClient
    private let courseStore: any VavruskaCourseStoring
    private let cache: any VavruskaCaching

    init(client: any VavruskaClient, courseStore: any VavruskaCourseStoring, cache: any VavruskaCaching) {
        self.client = client
        self.courseStore = courseStore
        self.cache = cache
    }

    func storedCourse() -> VavruskaStoredCourse? {
        try? courseStore.load()
    }

    func cachedSnapshot() -> VavruskaSnapshot? {
        try? cache.load()
    }

    func connect(password: String) async throws -> VavruskaStoredCourse {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VavruskaAppError.missingPassword }
        let course = try await client.login(password: trimmed)
        try? cache.clear()
        try courseStore.save(course)
        return course
    }

    func refresh(force: Bool, includeTicketLinks: Bool, now: Date = Date()) async throws -> VavruskaRefreshResult {
        guard let course = storedCourse() else { throw VavruskaAppError.notConnected }
        var snapshot = cachedSnapshot() ?? VavruskaSnapshot()
        var failed = false

        func isDue(_ fetchedAt: Date?, every interval: TimeInterval) -> Bool {
            guard let fetchedAt else { return true }
            let age = now.timeIntervalSince(fetchedAt)
            return force ? age > Policy.forcedFloor : age > interval
        }

        // 1. Lesson plan.
        let courseEnded = !snapshot.events.isEmpty && snapshot.events.allSatisfy { $0.end < now }
        if isDue(snapshot.calendarFetchedAt, every: courseEnded ? Policy.endedCalendar : Policy.calendar) {
            do {
                snapshot.events = try await client.fetchCalendar(course.calendarURL)
                snapshot.calendarUnavailable = false
                snapshot.calendarFetchedAt = now
            } catch VavruskaAPIError.calendarUnavailable {
                snapshot.calendarUnavailable = true
                snapshot.calendarFetchedAt = now
            } catch {
                failed = true
            }
        }

        // 2. Notice board.
        var noticeBoardChanged = false
        if isDue(snapshot.noticeBoardFetchedAt, every: Policy.noticeBoard) {
            do {
                let board = try await client.fetchNoticeBoard()
                noticeBoardChanged = board.digest != snapshot.noticeBoard?.digest
                snapshot.noticeBoard = board
                snapshot.noticeBoardFetchedAt = now
            } catch {
                failed = true
            }
        }

        // 3. Ticket sale times from the event pages the board links to.
        if noticeBoardChanged || isDue(snapshot.ticketSalesFetchedAt, every: Policy.ticketSales) {
            var paths: [String] = []
            for path in (snapshot.noticeBoard?.eventPagePaths ?? []) + [VavruskaLinks.fallbackEventPath]
            where !paths.contains(path) && paths.count < Policy.maxEventPages {
                paths.append(path)
            }

            var sales: [VavruskaTicketSale] = []
            var fetchedAny = false
            for path in paths {
                do {
                    let raws = try await client.fetchTicketSales(path: path)
                    fetchedAny = true
                    sales += raws.compactMap { resolve($0, course: course, events: snapshot.events, now: now) }
                } catch VavruskaAPIError.httpStatus(let status) where status == 404 || status == 410 {
                    fetchedAny = true
                } catch {
                    failed = true
                }
            }

            if fetchedAny {
                let previousLinks = Dictionary(snapshot.ticketSales.map { ($0.id, $0.ticketURL) }, uniquingKeysWith: { first, _ in first })
                var seen = Set<String>()
                snapshot.ticketSales = sales
                    .filter { seen.insert($0.id).inserted }
                    .map { sale in
                        var sale = sale
                        sale.ticketURL = previousLinks[sale.id] ?? nil
                        return sale
                    }
                    .sorted { $0.saleStart < $1.saleStart }
                snapshot.ticketSalesFetchedAt = now
            }
        }

        // 4. Direct ticket links appear on /vstupenky/ only once a sale is live.
        let needsLinks = snapshot.ticketSales.contains { sale in
            sale.ticketURL == nil && sale.eventStart > now && sale.saleStart <= now.addingTimeInterval(2 * 60 * 60)
        }
        if includeTicketLinks, needsLinks, isDue(snapshot.ticketLinksFetchedAt, every: Policy.ticketLinks) {
            do {
                let links = try await client.fetchTicketLinks()
                snapshot.ticketSales = snapshot.ticketSales.map { sale in
                    var sale = sale
                    if sale.ticketURL == nil {
                        sale.ticketURL = Self.ticketLink(for: sale.eventStart, in: links)
                    }
                    return sale
                }
                snapshot.ticketLinksFetchedAt = now
            } catch {
                failed = true
            }
        }

        // A disconnect while requests were in flight must not resurrect the cache.
        guard storedCourse()?.calendarURL == course.calendarURL else { throw VavruskaAppError.notConnected }
        try? cache.save(snapshot)
        return VavruskaRefreshResult(snapshot: snapshot, failed: failed)
    }

    func disconnect() {
        try? courseStore.clear()
        try? cache.clear()
    }

    func clearCache() {
        try? cache.clear()
    }

    // MARK: - Ticket sales

    private func resolve(
        _ raw: VavruskaRawTicketSale,
        course: VavruskaStoredCourse,
        events: [VavruskaEvent],
        now: Date
    ) -> VavruskaTicketSale? {
        let anchors = events.filter(\.kind.isEvent)
        guard let eventStart = VavruskaDateInference.eventStart(
            day: raw.eventDay, month: raw.eventMonth, hour: raw.startHour, minute: raw.startMinute,
            now: now, anchors: anchors
        ) else { return nil }

        let calendar = VavruskaDateInference.pragueCalendar
        let sameDayEvent = anchors.first { calendar.isDate($0.start, inSameDayAs: eventStart) }

        if let ownCode = course.courseCode.flatMap { VavruskaCourseCode($0) } {
            let listed = raw.courseCodes.compactMap { VavruskaCourseCode($0) }
            guard listed.contains(where: { $0.matches(ownCode) }) else { return nil }
        } else {
            guard sameDayEvent != nil else { return nil }
        }

        guard let saleStart = VavruskaDateInference.saleStart(
            day: raw.saleDay, month: raw.saleMonth, year: raw.saleYear,
            hour: raw.saleHour, minute: raw.saleMinute, eventStart: eventStart
        ) else { return nil }

        var eventEnd: Date?
        if let endHour = raw.endHour, let endMinute = raw.endMinute {
            let parts = calendar.dateComponents([.year, .month, .day], from: eventStart)
            eventEnd = VavruskaDateInference.date(
                year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0, hour: endHour, minute: endMinute
            )
            if let end = eventEnd, end <= eventStart {
                eventEnd = end.addingTimeInterval(24 * 60 * 60)
            }
        }

        return VavruskaTicketSale(
            id: VavruskaDateInference.eventKey(eventStart),
            eventTitle: sameDayEvent?.title ?? raw.pageTitle ?? AppL10n.string("vavruska.sale.defaultTitle"),
            eventStart: eventStart,
            eventEnd: eventEnd,
            // The lesson plan names the hall ("Obecní dům"); the event page only in a sentence.
            venue: sameDayEvent?.venue ?? raw.venue,
            saleStart: saleStart,
            ticketURL: nil
        )
    }

    private static func ticketLink(for eventStart: Date, in links: [VavruskaTicketLink]) -> URL? {
        let parts = VavruskaDateInference.pragueCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: eventStart)
        let sameDay = links.filter { $0.year == parts.year && $0.month == parts.month && $0.day == parts.day }
        if let exact = sameDay.first(where: { $0.hour == parts.hour && $0.minute == parts.minute }) {
            return exact.url
        }
        return sameDay.count == 1 ? sameDay[0].url : nil
    }
}

// MARK: - Mock

/// Runs the real parsers on fixtures with dates relative to now.
final class MockVavruskaClient: VavruskaClient {
    var calendarUnavailable: Bool
    var loginError: Error?

    init(calendarUnavailable: Bool = false, loginError: Error? = nil) {
        self.calendarUnavailable = calendarUnavailable
        self.loginError = loginError
    }

    func login(password: String) async throws -> VavruskaStoredCourse {
        if let loginError { throw loginError }
        guard password.uppercased() != "WRONG" else { throw VavruskaAPIError.invalidPassword }
        // A fresh login hands out a working link again.
        calendarUnavailable = false
        return PreviewData.vavruskaCourse
    }

    func fetchCalendar(_ url: URL) async throws -> [VavruskaEvent] {
        if calendarUnavailable { throw VavruskaAPIError.calendarUnavailable }
        return try VavruskaICSParser.parse(PreviewData.vavruskaICS())
    }

    func fetchNoticeBoard() async throws -> VavruskaNoticeBoard {
        VavruskaHTMLParser.parseNoticeBoard(PreviewData.vavruskaNoticeBoardHTML)
    }

    func fetchTicketSales(path: String) async throws -> [VavruskaRawTicketSale] {
        guard path == VavruskaLinks.fallbackEventPath else { return [] }
        return VavruskaHTMLParser.parseTicketSales(PreviewData.vavruskaEventPageHTML())
    }

    func fetchTicketLinks() async throws -> [VavruskaTicketLink] {
        VavruskaHTMLParser.parseTicketLinks(PreviewData.vavruskaTicketListingHTML())
    }
}
