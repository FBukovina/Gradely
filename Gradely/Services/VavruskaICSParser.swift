import Foundation

/// Just enough iCalendar to read the school's lesson plan: VEVENTs with UID,
/// SUMMARY, DESCRIPTION, LOCATION and DTSTART/DTEND. VTIMEZONE blocks are
/// skipped; zones come from the system database by TZID.
enum VavruskaICSParser {
    private struct Property {
        let parameters: [String: String]
        let value: String
    }

    static func parse(_ text: String) throws -> [VavruskaEvent] {
        let normalized = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard normalized.contains("BEGIN:VCALENDAR") else {
            throw VavruskaAPIError.calendarUnavailable
        }

        var lines: [String] = []
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }

        var blocks: [String] = []
        var properties: [String: Property] = [:]
        var events: [VavruskaEvent] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("BEGIN:") {
                let name = trimmed.dropFirst(6).uppercased()
                blocks.append(name)
                if name == "VEVENT" { properties = [:] }
                continue
            }
            if trimmed.uppercased().hasPrefix("END:") {
                if blocks.last == "VEVENT", let event = makeEvent(properties) {
                    events.append(event)
                }
                if !blocks.isEmpty { blocks.removeLast() }
                continue
            }
            guard blocks.last == "VEVENT", let (name, property) = parseProperty(line) else { continue }
            if properties[name] == nil {
                properties[name] = property
            }
        }

        return events.sorted { $0.start < $1.start }
    }

    // MARK: - Lines

    private static func parseProperty(_ line: String) -> (String, Property)? {
        var inQuotes = false
        var colon: String.Index?
        for index in line.indices {
            switch line[index] {
            case "\"": inQuotes.toggle()
            case ":" where !inQuotes:
                colon = index
            default: break
            }
            if colon != nil { break }
        }
        guard let colon else { return nil }

        let head = line[..<colon].split(separator: ";")
        guard let name = head.first?.uppercased(), !name.isEmpty else { return nil }
        var parameters: [String: String] = [:]
        for parameter in head.dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            parameters[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return (name, Property(parameters: parameters, value: String(line[line.index(after: colon)...])))
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            switch next {
            case "n", "N": result.append("\n")
            default: result.append(next)
            }
        }
        return result
    }

    // MARK: - Events

    private static func makeEvent(_ properties: [String: Property]) -> VavruskaEvent? {
        guard let uid = properties["UID"]?.value.trimmingCharacters(in: .whitespaces), !uid.isEmpty,
              let startProperty = properties["DTSTART"],
              let start = date(from: startProperty)
        else { return nil }

        let end: Date
        if let endProperty = properties["DTEND"], let parsed = date(from: endProperty), parsed >= start {
            end = parsed
        } else if isAllDay(startProperty) {
            end = start.addingTimeInterval(24 * 60 * 60)
        } else {
            end = start
        }

        let summary = unescape(properties["SUMMARY"]?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return VavruskaEvent(
            id: uid,
            title: displayTitle(summary),
            kind: VavruskaEventKind.classify(summary),
            venue: nonEmpty(properties["DESCRIPTION"].map { unescape($0.value) }),
            address: nonEmpty(properties["LOCATION"].map { unescape($0.value) }),
            start: start,
            end: end
        )
    }

    /// "Vyučovací lekce - TŠ Vavruška" → "Vyučovací lekce".
    static func displayTitle(_ summary: String) -> String {
        let stripped = summary.replacingOccurrences(
            of: #"\s*[-–—]\s*TŠ\s+Vavruška\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return stripped.isEmpty ? summary : stripped
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func isAllDay(_ property: Property) -> Bool {
        property.parameters["VALUE"]?.uppercased() == "DATE" || !property.value.contains("T")
    }

    /// `20260906T163000` with TZID, `…Z` (UTC), floating (Prague) or `20260906` (all day).
    private static func date(from property: Property) -> Date? {
        let value = property.value.trimmingCharacters(in: .whitespaces)
        let digits = value.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }

        func number(_ offset: Int, _ length: Int) -> Int? {
            let start = digits.index(digits.startIndex, offsetBy: offset)
            let end = digits.index(start, offsetBy: length, limitedBy: digits.endIndex) ?? digits.endIndex
            return Int(digits[start..<end])
        }

        var components = DateComponents()
        components.year = number(0, 4)
        components.month = number(4, 2)
        components.day = number(6, 2)
        if !isAllDay(property), digits.count >= 12 {
            components.hour = number(8, 2)
            components.minute = number(10, 2)
            components.second = digits.count >= 14 ? number(12, 2) : 0
        }

        var calendar = Calendar(identifier: .gregorian)
        if value.uppercased().hasSuffix("Z") {
            calendar.timeZone = TimeZone(identifier: "UTC")!
        } else if let identifier = property.parameters["TZID"], let zone = TimeZone(identifier: identifier) {
            calendar.timeZone = zone
        } else {
            calendar.timeZone = VavruskaDateInference.prague
        }
        return calendar.date(from: components)
    }
}
