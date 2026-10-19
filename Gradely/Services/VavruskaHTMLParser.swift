import Foundation

/// Regex-based readers for vavruska.info's server-rendered pages. Kept narrow
/// on purpose: each one targets a single, stable piece of markup.
enum VavruskaHTMLParser {
    enum LoginPage: Equatable {
        case course(code: String?, summary: String?, hash: String)
        case loginForm
        case unknown
    }

    // MARK: - Login

    /// The page after a successful login links `/pdf/rozpis-lekci/<hash>/cal/`
    /// and says "Rozvrh lekcí kurzu M04 · neděle 16.30 - 18.10".
    static func parseLogin(_ html: String) -> LoginPage {
        guard let hash = firstMatch(#"/pdf/rozpis-lekci/([0-9a-fA-F]{32})/cal/"#, in: html)?[1] else {
            return html.contains(#"name="heslo""#) ? .loginForm : .unknown
        }

        var code: String?
        var summary: String?
        if let range = html.range(of: "Rozvrh lekcí kurzu") {
            let tail = html[range.lowerBound...]
            let line = String(tail.prefix { $0 != "\n" })
                .components(separatedBy: "<br").first ?? ""
            let text = collapseWhitespace(decodeEntities(stripTags(line)))
            if let match = firstMatch(#"Rozvrh lekcí kurzu\s+(M\d+(?:-[A-Z])?)\s*(?:[·•|–-]\s*(.+))?"#, in: text) {
                code = match[1]
                summary = match[2].flatMap { $0.isEmpty ? nil : $0 }
            }
        }
        return .course(code: code, summary: summary, hash: hash.lowercased())
    }

    // MARK: - Notice board

    static func parseNoticeBoard(_ html: String) -> VavruskaNoticeBoard {
        let body = slice(html, from: #"class="article__body""#, untilAny: ["<div class=\"values-strip", "</main>", "<footer"])

        let updatedText = firstMatch(#"<p[^>]*article__meta[^>]*>(.*?)</p>"#, in: body)?[1]
            .map { collapseWhitespace(decodeEntities(stripTags($0))) }
        var updatedOn: Date?
        if let updatedText, let parts = firstMatch(#"(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})"#, in: updatedText),
           let day = parts[1].flatMap(Int.init), let month = parts[2].flatMap(Int.init), let year = parts[3].flatMap(Int.init) {
            updatedOn = VavruskaDateInference.date(year: year, month: month, day: day)
        }

        var items: [VavruskaNoticeItem] = []
        for chunk in body.components(separatedBy: "<hr") {
            guard let rawTitle = firstMatch(#"<h4[^>]*>(.*?)</h4>"#, in: chunk)?[1] else { continue }
            let title = collapseWhitespace(decodeEntities(stripTags(rawTitle)))
            guard !title.isEmpty else { continue }
            let paragraphs = allMatches(#"<p(?![^>]*article__meta)[^>]*>(.*?)</p>"#, in: chunk)
                .compactMap { $0[1] }
                .map { runs(fromParagraph: $0) }
                .filter { !$0.isEmpty }
            let plain = paragraphs.flatMap { $0.map(\.text) }.joined()
            items.append(VavruskaNoticeItem(id: fnv1a(title + "\n" + plain), title: title, paragraphs: paragraphs))
        }

        var eventPagePaths: [String] = []
        for match in allMatches(#"href="(?:https?://(?:www\.)?vavruska\.info)?(/akce/plesy/[a-z0-9-]+)/?""#, in: body) {
            if let path = match[1], !eventPagePaths.contains(path) {
                eventPagePaths.append(path)
            }
        }

        return VavruskaNoticeBoard(
            updatedOn: updatedOn,
            items: items,
            eventPagePaths: eventPagePaths,
            digest: fnv1a(([updatedText ?? ""] + items.map(\.id)).joined(separator: "|"))
        )
    }

    /// Turns one `<p>` into text runs, keeping links, bold and line breaks.
    static func runs(fromParagraph html: String) -> [VavruskaTextRun] {
        var runs: [VavruskaTextRun] = []
        var link: URL?
        var boldDepth = 0

        func append(_ text: String) {
            guard !text.isEmpty else { return }
            let isBold = boldDepth > 0
            if let last = runs.last, last.link == link, last.isBold == isBold {
                runs[runs.count - 1].text += text
            } else {
                runs.append(VavruskaTextRun(text: text, link: link, isBold: isBold))
            }
        }

        var index = html.startIndex
        while index < html.endIndex {
            if html[index] == "<", let close = html[index...].firstIndex(of: ">") {
                let tag = html[html.index(after: index)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
                let isClosing = tag.hasPrefix("/")
                let name = (isClosing ? tag.dropFirst() : Substring(tag)).prefix { $0.isLetter || $0.isNumber }.lowercased()
                switch (isClosing, name) {
                case (false, "a"): link = firstMatch(#"href\s*=\s*"([^"]*)""#, in: tag)?[1].flatMap { resolveLink($0) }
                case (true, "a"): link = nil
                case (false, "strong"), (false, "b"): boldDepth += 1
                case (true, "strong"), (true, "b"): boldDepth = max(0, boldDepth - 1)
                case (_, "br"): append("\n")
                default: break
                }
                index = html.index(after: close)
            } else {
                let next = html[index...].firstIndex(of: "<") ?? html.endIndex
                append(collapseWhitespace(decodeEntities(String(html[index..<next])), trimming: false))
                index = next
            }
        }

        // Tidy the whitespace that source indentation leaves around breaks and edges.
        for i in runs.indices {
            runs[i].text = runs[i].text
                .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
        }
        if let first = runs.indices.first {
            runs[first].text = String(runs[first].text.drop { $0.isWhitespace })
        }
        if let last = runs.indices.last {
            runs[last].text = String(runs[last].text.reversed().drop { $0.isWhitespace }.reversed())
        }
        return runs.filter { !$0.text.isEmpty }
    }

    // MARK: - Ticket sales

    private static let months = [
        "ledna", "února", "března", "dubna", "května", "června",
        "července", "srpna", "září", "října", "listopadu", "prosince"
    ]

    /// Pairs "18. října od 16:00 do 19:00 v Obecním domě pro kurz M04" with the
    /// "Prodej vstupenek začíná 12. 10. v 18.00" that follows it.
    static func parseTicketSales(_ html: String) -> [VavruskaRawTicketSale] {
        let pageTitle = firstMatch(#"<h1[^>]*>(.*?)</h1>"#, in: html)?[1]
            .map { collapseWhitespace(decodeEntities(stripTags($0))) }
        let text = visibleText(slice(html, from: "</h1>", untilAny: ["<div class=\"values-strip", "<footer"]))

        let eventPattern = #"(\d{1,2})\.\s*("# + months.joined(separator: "|")
            + #")\s+od\s+(\d{1,2})[.:](\d{2})(?:\s+do\s+(\d{1,2})[.:](\d{2}))?\s+((?:v|ve)\s+[^\n]+?)\s+pro\s+kurzy?\s+(M\d+(?:-[A-Z])?(?:\s*(?:,|a|i|\+|&)\s*M\d+(?:-[A-Z])?)*)"#
        let salePattern = #"Prodej\s+vstupenek\s+(?:začíná|začne|bude\s+zahájen)\s+(\d{1,2})\.\s*(\d{1,2})\.(?:\s*(\d{4}))?\s*(?:v|ve|od)?\s*(\d{1,2})[.:](\d{2})"#
        let events = allMatchesWithRanges(eventPattern, in: text)
        let sales = allMatchesWithRanges(salePattern, in: text)

        var result: [VavruskaRawTicketSale] = []
        for (index, event) in events.enumerated() {
            let nextStart = index + 1 < events.count ? events[index + 1].range.lowerBound : text.endIndex
            guard let sale = sales.first(where: { $0.range.lowerBound >= event.range.upperBound && $0.range.lowerBound < nextStart }),
                  let day = event.groups[1].flatMap(Int.init),
                  let monthName = event.groups[2]?.lowercased(),
                  let month = months.firstIndex(of: monthName).map({ $0 + 1 }),
                  let startHour = event.groups[3].flatMap(Int.init),
                  let startMinute = event.groups[4].flatMap(Int.init),
                  let saleDay = sale.groups[1].flatMap(Int.init),
                  let saleMonth = sale.groups[2].flatMap(Int.init),
                  let saleHour = sale.groups[4].flatMap(Int.init),
                  let saleMinute = sale.groups[5].flatMap(Int.init)
            else { continue }

            let codes = allMatches(#"M\d+(?:-[A-Z])?"#, in: event.groups[8] ?? "").compactMap { $0[0] }
            result.append(VavruskaRawTicketSale(
                eventDay: day,
                eventMonth: month,
                startHour: startHour,
                startMinute: startMinute,
                endHour: event.groups[5].flatMap(Int.init),
                endMinute: event.groups[6].flatMap(Int.init),
                venue: event.groups[7].map { collapseWhitespace($0) },
                courseCodes: codes,
                saleDay: saleDay,
                saleMonth: saleMonth,
                saleYear: sale.groups[3].flatMap(Int.init),
                saleHour: saleHour,
                saleMinute: saleMinute,
                pageTitle: pageTitle
            ))
        }
        return result
    }

    /// `/vstupenky/prodlouzena-19-10-2026-od-2000/` links on the ticket listing.
    static func parseTicketLinks(_ html: String) -> [VavruskaTicketLink] {
        var links: [VavruskaTicketLink] = []
        for match in allMatches(#"href="(/vstupenky/[a-z0-9-]+?-(\d{1,2})-(\d{1,2})-(\d{4})-od-(\d{3,4})/?)(?:#[^"]*)?""#, in: html) {
            guard let path = match[1], let url = VavruskaLinks.page(path),
                  let day = match[2].flatMap(Int.init), let month = match[3].flatMap(Int.init),
                  let year = match[4].flatMap(Int.init), let time = match[5].flatMap(Int.init)
            else { continue }
            let link = VavruskaTicketLink(url: url, day: day, month: month, year: year, hour: time / 100, minute: time % 100)
            if !links.contains(link) { links.append(link) }
        }
        return links
    }

    // MARK: - Text helpers

    static func visibleText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"(?s)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"</(p|li|h\d|div|tr)>|<hr[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        text = decodeEntities(stripTags(text))
        return text
            .components(separatedBy: "\n")
            .map { collapseWhitespace($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    static func collapseWhitespace(_ text: String, trimming: Bool = true) -> String {
        let collapsed = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return trimming ? collapsed.trimmingCharacters(in: .whitespaces) : collapsed
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "bdquo": "„", "ldquo": "“", "rdquo": "”",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "middot": "·", "lowast": "∗", "times": "×"
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") {
                let name = text[text.index(after: index)..<semicolon]
                var replacement: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    replacement = UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String($0) }
                } else if name.hasPrefix("#") {
                    replacement = UInt32(name.dropFirst(), radix: 10).flatMap { Unicode.Scalar($0) }.map { String($0) }
                } else {
                    replacement = namedEntities[String(name)]
                }
                if let replacement {
                    result += replacement
                    index = text.index(after: semicolon)
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result.precomposedStringWithCanonicalMapping
    }

    private static func resolveLink(_ href: String) -> URL? {
        let decoded = decodeEntities(href).trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: decoded, relativeTo: VavruskaLinks.base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme)
        else { return nil }
        return url
    }

    private static func slice(_ html: String, from marker: String, untilAny endMarkers: [String]) -> String {
        guard let start = html.range(of: marker) else { return html }
        let tail = html[start.upperBound...]
        let end = endMarkers.compactMap { tail.range(of: $0)?.lowerBound }.min() ?? tail.endIndex
        return String(tail[..<end])
    }

    /// FNV-1a 64-bit; `Hasher` is seeded per launch, so it can't fingerprint across runs.
    static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Regex

    private static var regexCache: [String: NSRegularExpression] = [:]

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        if let cached = regexCache[pattern] { return cached }
        let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        regexCache[pattern] = compiled
        return compiled
    }

    private struct Match {
        let range: Range<String.Index>
        let groups: [String?]
    }

    private static func allMatchesWithRanges(_ pattern: String, in text: String) -> [Match] {
        guard let regex = regex(pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let groups = (0..<result.numberOfRanges).map { index -> String? in
                Range(result.range(at: index), in: text).map { String(text[$0]) }
            }
            return Match(range: range, groups: groups)
        }
    }

    private static func allMatches(_ pattern: String, in text: String) -> [[String?]] {
        allMatchesWithRanges(pattern, in: text).map(\.groups)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = regex(pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
