import Foundation

/// TŠ Vavruška (vavruska.info) youth dance course integration. The site has no
/// API: the lesson plan is an ICS file behind a password from the course card,
/// everything else is scraped from public pages. Device-local only.
enum VavruskaSettings {
    static let enabledKey = "settings.showVavruska"
    static let ticketAlertsKey = "gradey.vavruska.ticketAlerts.enabled.v1"
    static let seenNoticeDigestKey = "gradey.vavruska.seenNoticeDigest.v1"
}

enum VavruskaLinks {
    static let base = URL(string: "https://vavruska.info")!
    static let schedulePage = URL(string: "https://vavruska.info/rozvrh-lekci-mladez/")!
    static let login = URL(string: "https://vavruska.info/rozvrh-lekci-mladez/?action=login")!
    static let noticeBoard = URL(string: "https://vavruska.info/nastenka/")!
    static let tickets = URL(string: "https://vavruska.info/vstupenky/")!
    static let clothing = URL(string: "https://vavruska.info/obleceni/")!
    static let gallery = URL(string: "https://galerie.vavruska.info")!
    static let office = URL(string: "mailto:kancelar@vavruska.info")!
    /// Linked from the notice board every autumn; kept as a fallback for when it isn't.
    static let fallbackEventPath = "/akce/plesy/prodlouzena-mladez"

    static func calendarURL(hash: String) -> URL {
        URL(string: "https://vavruska.info/pdf/rozpis-lekci/\(hash)/cal/")!
    }

    static func pdfURL(hash: String) -> URL {
        URL(string: "https://vavruska.info/pdf/rozpis-lekci/\(hash)/")!
    }

    static func page(_ path: String) -> URL? {
        URL(string: path, relativeTo: base)?.absoluteURL
    }

    /// The client only ever fetches from the school's own host.
    static func isAllowedFetchURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "vavruska.info" || host == "www.vavruska.info"
    }
}

/// What survives a login: the course and its capability ICS link. The card
/// password itself is never stored.
struct VavruskaStoredCourse: Codable, Equatable {
    var courseCode: String?
    /// e.g. "neděle 16.30 - 18.10"
    var scheduleSummary: String?
    var calendarURL: URL
    var pdfURL: URL?
    var connectedAt: Date
}

enum VavruskaEventKind: String, Codable {
    case lesson
    case specialLesson
    case extendedLesson
    case ball

    /// Prodloužená and the final ball: the ones with tickets for guests.
    var isEvent: Bool { self == .extendedLesson || self == .ball }

    var iconName: String {
        switch self {
        case .lesson: "music-note-03"
        case .specialLesson: "music-note-01"
        case .extendedLesson: "party"
        case .ball: "flower"
        }
    }

    static func classify(_ summary: String) -> VavruskaEventKind {
        let folded = summary.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
        if folded.contains("ples") { return .ball }
        if folded.contains("prodlouzen") { return .extendedLesson }
        if folded.contains("vyucovaci") { return .lesson }
        return .specialLesson
    }
}

struct VavruskaEvent: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let kind: VavruskaEventKind
    let venue: String?
    let address: String?
    let start: Date
    let end: Date
}

struct VavruskaTextRun: Codable, Equatable {
    var text: String
    var link: URL?
    var isBold: Bool
}

struct VavruskaNoticeItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let paragraphs: [[VavruskaTextRun]]
}

struct VavruskaNoticeBoard: Codable, Equatable {
    let updatedOn: Date?
    let items: [VavruskaNoticeItem]
    /// `/akce/plesy/…` pages linked from the board; they carry ticket sale times.
    let eventPagePaths: [String]
    /// Stable fingerprint of the board's content, used for the "new" badge.
    let digest: String
}

/// A ticket sale as written on an event page, before years are inferred.
struct VavruskaRawTicketSale: Equatable {
    let eventDay: Int
    let eventMonth: Int
    let startHour: Int
    let startMinute: Int
    let endHour: Int?
    let endMinute: Int?
    let venue: String?
    let courseCodes: [String]
    let saleDay: Int
    let saleMonth: Int
    let saleYear: Int?
    let saleHour: Int
    let saleMinute: Int
    let pageTitle: String?
}

struct VavruskaTicketSale: Codable, Equatable, Identifiable {
    /// Event start in Prague time, "yyyyMMdd-HHmm".
    let id: String
    let eventTitle: String
    let eventStart: Date
    let eventEnd: Date?
    let venue: String?
    let saleStart: Date
    var ticketURL: URL?
}

/// A `/vstupenky/<slug>-D-M-YYYY-od-HMM/` link from the ticket listing.
struct VavruskaTicketLink: Equatable {
    let url: URL
    let day: Int
    let month: Int
    let year: Int
    let hour: Int
    let minute: Int
}

/// Course codes look like "M04", "M18-A" or "M121".
struct VavruskaCourseCode: Hashable {
    let number: Int
    let section: String?

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.hasPrefix("M") else { return nil }
        let parts = trimmed.dropFirst().split(separator: "-", maxSplits: 1)
        guard let first = parts.first, let number = Int(first) else { return nil }
        self.number = number
        section = parts.count > 1 ? String(parts[1]) : nil
    }

    /// "M18" covers both "M18-A" and "M18-B"; "M18-A" and "M18-B" differ.
    func matches(_ other: VavruskaCourseCode) -> Bool {
        guard number == other.number else { return false }
        guard let section, let otherSection = other.section else { return true }
        return section == otherSection
    }
}

struct VavruskaSnapshot: Codable, Equatable {
    var events: [VavruskaEvent] = []
    var calendarFetchedAt: Date?
    /// The ICS link stopped working (new season, new password): reconnect.
    var calendarUnavailable = false
    var noticeBoard: VavruskaNoticeBoard?
    var noticeBoardFetchedAt: Date?
    var ticketSales: [VavruskaTicketSale] = []
    var ticketSalesFetchedAt: Date?
    var ticketLinksFetchedAt: Date?

    var lastFetchedAt: Date? {
        [calendarFetchedAt, noticeBoardFetchedAt, ticketSalesFetchedAt].compactMap { $0 }.max()
    }
}
