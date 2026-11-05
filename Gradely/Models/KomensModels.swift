import Foundation

// MARK: - Bakaláři payload

/// `POST api/3/komens/messages/received` and `…/noticeboard` both answer with this.
struct KomensResponse: Codable, Equatable {
    var messages: [KomensMessageDTO]

    enum CodingKeys: String, CodingKey {
        case messages = "Messages"
    }

    init(messages: [KomensMessageDTO]) {
        self.messages = messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([KomensMessageDTO].self, forKey: .messages) ?? []
    }
}

struct KomensMessageDTO: Codable, Equatable {
    let id: String
    let title: String?
    /// HTML.
    let text: String?
    let sentDate: String?
    let sender: KomensSenderDTO?
    let relevantName: String?
    let attachments: [SchoolAttachmentDTO]
    var read: Bool
    /// Hidden by the student in the official app.
    let hidden: Bool

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case title = "Title"
        case text = "Text"
        case sentDate = "SentDate"
        case sender = "Sender"
        case relevantName = "RelevantName"
        case attachments = "Attachments"
        case read = "Read"
        case hidden = "Hidden"
    }

    init(
        id: String,
        title: String?,
        text: String?,
        sentDate: String?,
        sender: KomensSenderDTO?,
        relevantName: String? = nil,
        attachments: [SchoolAttachmentDTO] = [],
        read: Bool = true,
        hidden: Bool = false
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.sentDate = sentDate
        self.sender = sender
        self.relevantName = relevantName
        self.attachments = attachments
        self.read = read
        self.hidden = hidden
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        sentDate = try? container.decodeIfPresent(String.self, forKey: .sentDate)
        sender = try? container.decodeIfPresent(KomensSenderDTO.self, forKey: .sender)
        relevantName = try? container.decodeIfPresent(String.self, forKey: .relevantName)
        attachments = (try? container.decodeIfPresent([SchoolAttachmentDTO].self, forKey: .attachments)) ?? []
        read = (try? container.decodeIfPresent(Bool.self, forKey: .read)) ?? true
        hidden = (try? container.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
    }
}

struct KomensSenderDTO: Codable, Equatable {
    let id: String?
    let type: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case name = "Name"
    }
}

/// Both lists, cached together so the unread count is there after a relaunch.
struct KomensSnapshot: Codable, Equatable {
    static let cachePrefix = "komens-cache"

    var received: [KomensMessageDTO]
    var noticeboard: [KomensMessageDTO]

    mutating func markRead(id: String) {
        for index in received.indices where received[index].id == id { received[index].read = true }
        for index in noticeboard.indices where noticeboard[index].id == id { noticeboard[index].read = true }
    }
}

// MARK: - App model

enum KomensBox: String, CaseIterable, Identifiable, Sendable {
    case received
    case noticeboard

    var id: Self { self }
}

/// A Komens message from the school, read-only apart from being read.
struct KomensMessage: Identifiable, Equatable, Sendable {
    let messageID: String
    let box: KomensBox
    let title: String?
    let body: String
    let senderName: String?
    let sentAt: Date?
    var isRead: Bool
    let attachments: [SchoolAttachment]

    /// The same message can be both received and pinned to the noticeboard.
    var id: String { box.rawValue + "\u{1F}" + messageID }

    init(_ dto: KomensMessageDTO, box: KomensBox) {
        messageID = dto.id
        self.box = box
        title = Self.trimmed(dto.title.map { KomensText.decodeEntities($0) })
        body = KomensText.plainText(fromHTML: dto.text ?? "")
        senderName = Self.trimmed(dto.sender?.name) ?? Self.trimmed(dto.relevantName)
        sentAt = Homework.schoolDate(dto.sentDate)
        isRead = dto.read
        attachments = dto.attachments.map {
            SchoolAttachment(id: $0.id, name: Self.trimmed($0.name) ?? $0.id, size: $0.size.flatMap { $0 > 0 ? $0 : nil })
        }
    }

    /// The title, or the first line for messages without one (excuse notes have none).
    var heading: String {
        if let title { return title }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.isEmpty ? AppL10n.string("komens.untitled") : firstLine
    }

    /// The text under the heading in a list row.
    var preview: String {
        let lines = body.split(whereSeparator: \.isNewline).map(String.init)
        return (title == nil ? lines.dropFirst() : lines[...]).joined(separator: " ")
    }

    static func sorted(_ messages: [KomensMessage]) -> [KomensMessage] {
        messages.sorted {
            switch ($0.sentAt, $1.sentAt) {
            case let (left?, right?) where left != right: return left > right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.messageID > $1.messageID
            }
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - HTML

/// Komens text arrives as HTML from the school's editor. Gradey shows it as
/// plain paragraphs and lists, with links kept tappable.
enum KomensText {
    static func plainText(fromHTML html: String) -> String {
        guard html.range(of: "<[a-zA-Z/!]", options: .regularExpression) != nil else {
            return tidy(decodeEntities(html))
        }
        // In HTML, line breaks in the source are just spaces.
        var text = html.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "<!--.*?-->|<(script|style)[^>]*>.*?</\\1\\s*>", with: "", options: [.regularExpression, .caseInsensitive]
        )
        text = replacingLinks(in: text)
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "\n• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(
            of: "</?(p|div|ul|ol|table|tr|h[1-6]|blockquote|section|article)(\\s[^>]*)?>", with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "</t[dh]\\s*>", with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return tidy(decodeEntities(text))
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"),
              let regex = try? NSRegularExpression(pattern: "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]{1,31});")
        else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result), let nameRange = Range(match.range(at: 1), in: result) else { continue }
            let name = String(result[nameRange])
            let replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[name]
            }
            if let replacement { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }

    /// `<a href="…">text</a>` keeps the address when the text doesn't show it.
    private static func replacingLinks(in html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "<a\\s[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a\\s*>", options: [.caseInsensitive]
        ) else { return html }
        var result = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range, in: result),
                  let urlRange = Range(match.range(at: 1), in: result),
                  let labelRange = Range(match.range(at: 2), in: result) else { continue }
            let address = decodeEntities(String(result[urlRange])).replacingOccurrences(of: "mailto:", with: "")
            let label = String(result[labelRange])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let replacement = label.isEmpty || decodeEntities(label).contains(address) ? (label.isEmpty ? address : label) : "\(label) (\(address))"
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    /// Trims each line and keeps at most one empty line between paragraphs.
    private static func tidy(_ text: String) -> String {
        var lines: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if let last = lines.last, !last.isEmpty { lines.append("") }
            } else {
                lines.append(trimmed)
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let namedEntities: [String: String] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·",
        "bdquo": "„", "ldquo": "“", "rdquo": "”", "sbquo": "‚", "lsquo": "‘", "rsquo": "’",
        "laquo": "«", "raquo": "»", "euro": "€", "times": "×", "deg": "°", "copy": "©", "shy": "",
        "aacute": "á", "Aacute": "Á", "eacute": "é", "Eacute": "É", "iacute": "í", "Iacute": "Í",
        "oacute": "ó", "Oacute": "Ó", "uacute": "ú", "Uacute": "Ú", "yacute": "ý", "Yacute": "Ý",
        "ecaron": "ě", "Ecaron": "Ě", "scaron": "š", "Scaron": "Š", "ccaron": "č", "Ccaron": "Č",
        "rcaron": "ř", "Rcaron": "Ř", "zcaron": "ž", "Zcaron": "Ž", "dcaron": "ď", "Dcaron": "Ď",
        "tcaron": "ť", "Tcaron": "Ť", "ncaron": "ň", "Ncaron": "Ň", "uring": "ů", "Uring": "Ů",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "lcaron": "ľ", "Lcaron": "Ľ", "ocirc": "ô", "Ocirc": "Ô", "lacute": "ĺ", "racute": "ŕ"
    ]
}
