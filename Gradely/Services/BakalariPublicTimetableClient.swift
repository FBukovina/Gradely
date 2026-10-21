import Foundation

/// A class in a school's public Bakaláři timetable (`/Timetable/Public`).
struct PublicTimetableClass: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
}

/// The public timetable only offers this week, next week and the permanent one.
enum PublicTimetableTerm: String, Sendable {
    case actual = "Actual"
    case next = "Next"
    case permanent = "Permanent"
}

enum PublicTimetableError: LocalizedError, Equatable {
    case notPublished
    case unexpectedPage
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notPublished: AppL10n.string("friends.public.error.notPublished")
        case .unexpectedPage: AppL10n.string("friends.public.error.unexpectedPage")
        case .httpStatus(let status): String(format: AppL10n.string("friends.public.error.status"), status)
        }
    }
}

protocol BakalariPublicTimetableClient {
    func fetchClasses(schoolURL: URL) async throws -> [PublicTimetableClass]
    func fetchTimetable(schoolURL: URL, classID: String, term: PublicTimetableTerm, weekStart: Date) async throws -> TimetableResponse
}

/// Reads the school's public timetable pages, no sign-in. Schools can turn
/// this off, in which case Bakaláři redirects to its login page.
final class URLSessionBakalariPublicTimetableClient: BakalariPublicTimetableClient {
    private static let maxResponseBytes = 3 * 1024 * 1024
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchClasses(schoolURL: URL) async throws -> [PublicTimetableClass] {
        let html = try await page(schoolURL.appending(path: "Timetable/Public"))
        let classes = BakalariPublicTimetableParser.classes(in: html)
        guard !classes.isEmpty else { throw PublicTimetableError.notPublished }
        return classes
    }

    func fetchTimetable(schoolURL: URL, classID: String, term: PublicTimetableTerm, weekStart: Date) async throws -> TimetableResponse {
        let url = schoolURL.appending(path: "Timetable/Public/\(term.rawValue)/Class/\(classID)")
        let html = try await page(url)
        guard let response = BakalariPublicTimetableParser.timetable(in: html, term: term, weekStart: weekStart) else {
            throw PublicTimetableError.unexpectedPage
        }
        return response
    }

    private func page(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("cs-CZ,cs;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PublicTimetableError.unexpectedPage }
        // A school that doesn't publish its timetable sends visitors to sign in.
        if http.url?.path.lowercased().contains("login") == true { throw PublicTimetableError.notPublished }
        if http.statusCode == 404 || http.statusCode == 401 || http.statusCode == 403 { throw PublicTimetableError.notPublished }
        guard (200..<300).contains(http.statusCode) else { throw PublicTimetableError.httpStatus(http.statusCode) }
        guard data.count <= Self.maxResponseBytes, let html = String(data: data, encoding: .utf8) else {
            throw PublicTimetableError.unexpectedPage
        }
        return html
    }
}

/// Turns the public timetable page into the same payload the Bakaláři API
/// returns, so friends' timetables go through `TimetableMapper` like yours.
/// The page embeds its data as `const timetableData = {…};`.
enum BakalariPublicTimetableParser {
    static func classes(in html: String) -> [PublicTimetableClass] {
        guard let start = html.range(of: "id=\"selectedClass\""),
              let end = html[start.upperBound...].range(of: "</select>")
        else { return [] }
        let select = html[start.upperBound..<end.lowerBound]
        var result: [PublicTimetableClass] = []
        var cursor = select.startIndex
        while let option = select[cursor...].range(of: "<option value=\"") {
            guard let valueEnd = select[option.upperBound...].firstIndex(of: "\""),
                  let tagEnd = select[valueEnd...].firstIndex(of: ">"),
                  let close = select[tagEnd...].range(of: "</option>")
            else { break }
            let id = VavruskaHTMLParser.decodeEntities(String(select[option.upperBound..<valueEnd])).trimmingCharacters(in: .whitespaces)
            let name = VavruskaHTMLParser.collapseWhitespace(
                VavruskaHTMLParser.decodeEntities(String(select[select.index(after: tagEnd)..<close.lowerBound]))
            )
            if !id.isEmpty, !name.isEmpty { result.append(PublicTimetableClass(id: id, name: name)) }
            cursor = close.upperBound
        }
        return result
    }

    static func timetable(in html: String, term: PublicTimetableTerm, weekStart: Date) -> TimetableResponse? {
        guard let json = embeddedJSON(in: html, after: "const timetableData"),
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8))
        else { return nil }
        return response(from: payload, term: term, weekStart: weekStart)
    }

    // MARK: - Mapping

    static func response(from payload: Payload, term: PublicTimetableTerm, weekStart: Date) -> TimetableResponse {
        var subjects: [String: TimetableEntity] = [:]
        var teachers: [String: TimetableEntity] = [:]
        var rooms: [String: TimetableEntity] = [:]
        var groups: [String: TimetableGroup] = [:]
        var cycles: [String: TimetableEntity] = [:]

        let headerHours = payload.hours ?? []
        var hours = headerHours.enumerated().map { index, header in
            TimetableHour(
                id: index + 1,
                caption: header.caption ?? "\(index + 1)",
                beginTime: header.beginTime ?? "",
                endTime: header.endTime ?? ""
            )
        }
        var hourByMinute = Dictionary(
            hours.compactMap { hour in minutes(hour.beginTime).map { ($0, hour.id) } },
            uniquingKeysWith: { first, _ in first }
        )

        let days = (payload.days ?? []).enumerated().map { index, day -> TimetableDayDTO in
            let dayOfWeek = day.dayAbbrev.flatMap(TimetableGridReconstructor.weekday(for:)) ?? index + 1
            let date = term == .permanent
                ? ""
                : TimetableDates.apiDateString(TimetableDates.weekCalendar.date(byAdding: .day, value: dayOfWeek - 1, to: weekStart) ?? weekStart)
            if day.dayOff == true {
                return TimetableDayDTO(dayOfWeek: dayOfWeek, date: date, dayDescription: day.dayOffName ?? "", dayType: "Holiday")
            }

            var atoms: [TimetableAtom] = []
            for hour in day.hours ?? [] {
                let beginMinute = hour.beginTimeValue ?? minutes(hour.begin ?? "")
                let hourID: Int
                if let beginMinute, let known = hourByMinute[beginMinute] {
                    hourID = known
                } else {
                    // An hour the header doesn't list (a zero lesson, say).
                    hourID = (hours.map(\.id).max() ?? 0) + 1
                    hours.append(TimetableHour(id: hourID, caption: "", beginTime: clock(hour.begin), endTime: clock(hour.end)))
                    if let beginMinute { hourByMinute[beginMinute] = hourID }
                }

                if (hour.atoms ?? []).isEmpty, let text = hour.hourText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    // A class-wide event in place of lessons (a trip, an exam day).
                    let subjectID = "event-\(text)"
                    subjects[subjectID] = TimetableEntity(id: subjectID, abbrev: text, name: text)
                    atoms.append(TimetableAtom(hourID: hourID, subjectID: subjectID, change: TimetableChange(changeType: "Event", description: text)))
                    continue
                }

                for atom in hour.atoms ?? [] {
                    let removed = atom.type?.lowercased() == "removed"
                    var subjectAbbrev = atom.subjectAbbrev
                    var subjectName = atom.subjectText
                    var teacherName = atom.teacherFullname
                    if removed, let info = atom.changeInfo, let open = info.firstIndex(of: "("), let close = info.lastIndex(of: ")"), open < close {
                        // "Vyjmuto z rozvrhu (ČJL, Grausgruberová Romana)"
                        let parts = info[info.index(after: open)..<close].split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        subjectAbbrev = parts.first
                        subjectName = parts.first
                        teacherName = parts.count > 1 ? parts[1] : nil
                    }

                    let subjectID = entityID(subjectAbbrev, subjectName)
                    if let subjectID {
                        subjects[subjectID] = TimetableEntity(id: subjectID, abbrev: subjectAbbrev ?? subjectName ?? "", name: subjectName ?? subjectAbbrev ?? "")
                    }
                    let teacherID = entityID(atom.teacher, teacherName)
                    if let teacherID {
                        teachers[teacherID] = TimetableEntity(id: teacherID, abbrev: atom.teacher ?? teacherName ?? "", name: teacherName ?? atom.teacher ?? "")
                    }
                    let roomID = entityID(atom.room, atom.roomFullName)
                    if let roomID {
                        rooms[roomID] = TimetableEntity(id: roomID, abbrev: atom.room ?? atom.roomFullName ?? "", name: atom.roomFullName ?? atom.room ?? "")
                    }
                    let groupIDs = groupNames(atom.groupsNames).map { name in
                        let id = "g-\(name)"
                        groups[id] = TimetableGroup(id: id, abbrev: name, name: name)
                        return id
                    }
                    let cycleIDs = (atom.cycleText?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }.map { text -> [String] in
                        let id = "c-\(text)"
                        cycles[id] = TimetableEntity(id: id, abbrev: text, name: text)
                        return [id]
                    } ?? []

                    atoms.append(TimetableAtom(
                        hourID: hourID,
                        groupIDs: groupIDs,
                        subjectID: subjectID,
                        teacherID: teacherID,
                        roomID: roomID,
                        cycleIDs: cycleIDs,
                        change: change(for: atom, removed: removed),
                        theme: atom.theme
                    ))
                }
            }
            return TimetableDayDTO(atoms: atoms, dayOfWeek: dayOfWeek, date: date)
        }

        return TimetableResponse(
            hours: hours,
            days: days,
            groups: groups.values.sorted { $0.id < $1.id },
            subjects: subjects.values.sorted { $0.id < $1.id },
            teachers: teachers.values.sorted { $0.id < $1.id },
            rooms: rooms.values.sorted { $0.id < $1.id },
            cycles: cycles.values.sorted { $0.id < $1.id }
        )
    }

    /// Group names on an atom, "AJ1" or "AJ1, NJ".
    static func groupNames(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func change(for atom: Payload.Atom, removed: Bool) -> TimetableChange? {
        let description = atom.changeInfo?.trimmingCharacters(in: .whitespacesAndNewlines)
        if removed {
            return TimetableChange(changeType: "Removed", description: description)
        }
        guard atom.hasChanged == true else { return nil }
        let tooltipCode = atom.tooltipDetails
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            .flatMap { $0["infoChangeCode"] as? String }
        let code = tooltipCode ?? {
            switch atom.infoChangeCode {
            case 0: "Removed"
            case 3: "Added"
            case 4: "RoomChanged"
            default: "Substitution"
            }
        }()
        return TimetableChange(changeType: code, description: description)
    }

    private static func entityID(_ abbrev: String?, _ name: String?) -> String? {
        let key = [abbrev, name].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "|")
        return key.isEmpty ? nil : key
    }

    /// "8:00" or "08:00:00" to minutes after midnight.
    private static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count >= 2 ? parts[0] * 60 + parts[1] : nil
    }

    private static func clock(_ value: String?) -> String {
        guard let value, let total = minutes(value) else { return "" }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The JSON object literal assigned after `marker`, found by matching braces
    /// outside strings (the data itself contains `;` and `}` in text).
    static func embeddedJSON(in html: String, after marker: String) -> String? {
        guard let markerRange = html.range(of: marker),
              let start = html[markerRange.upperBound...].firstIndex(of: "{")
        else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < html.endIndex {
            let character = html[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(html[start...index]) }
            }
            index = html.index(after: index)
        }
        return nil
    }

    // MARK: - Page model

    struct Payload: Decodable {
        let days: [Day]?
        let hours: [HeaderHour]?

        enum CodingKeys: String, CodingKey {
            case days = "Days"
            case hours = "Hours"
        }

        struct HeaderHour: Decodable {
            let caption: String?
            let beginTime: String?
            let endTime: String?

            enum CodingKeys: String, CodingKey {
                case caption = "Caption"
                case beginTime = "BeginTime"
                case endTime = "EndTime"
            }
        }

        struct Day: Decodable {
            let dayAbbrev: String?
            let dayOff: Bool?
            let dayOffName: String?
            let hours: [Hour]?

            enum CodingKeys: String, CodingKey {
                case dayAbbrev = "DayAbbrev"
                case dayOff = "DayOff"
                case dayOffName = "DayOffName"
                case hours = "Hours"
            }
        }

        struct Hour: Decodable {
            let atoms: [Atom]?
            let hourText: String?
            let begin: String?
            let end: String?
            let beginTimeValue: Int?

            enum CodingKeys: String, CodingKey {
                case atoms = "Atoms"
                case hourText = "HourText"
                case begin = "Begin"
                case end = "End"
                case beginTimeValue = "BeginTimeValue"
            }
        }

        struct Atom: Decodable {
            let type: String?
            let subjectText: String?
            let subjectAbbrev: String?
            let teacher: String?
            let teacherFullname: String?
            let room: String?
            let roomFullName: String?
            let groupsNames: String?
            let theme: String?
            let changeInfo: String?
            let hasChanged: Bool?
            let infoChangeCode: Int?
            let cycleText: String?
            let tooltipDetails: String?

            enum CodingKeys: String, CodingKey {
                case type = "Type"
                case subjectText = "SubjectText"
                case subjectAbbrev = "SubjectAbbrev"
                case teacher = "Teacher"
                case teacherFullname = "TeacherFullname"
                case room = "Room"
                case roomFullName = "RoomFullName"
                case groupsNames = "GroupsNames"
                case theme = "Theme"
                case changeInfo = "ChangeInfo"
                case hasChanged = "HasChanged"
                case infoChangeCode = "InfoChangeCode"
                case cycleText = "CycleText"
                case tooltipDetails = "TooltipDetails"
            }
        }
    }
}

/// Demo classes for `-uiTestingMockAPI`.
final class MockBakalariPublicTimetableClient: BakalariPublicTimetableClient {
    func fetchClasses(schoolURL: URL) async throws -> [PublicTimetableClass] {
        [PublicTimetableClass(id: "A1", name: "1.A"), PublicTimetableClass(id: "B2", name: "2.B"), PublicTimetableClass(id: "C3", name: "3.C")]
    }

    func fetchTimetable(schoolURL: URL, classID: String, term: PublicTimetableTerm, weekStart: Date) async throws -> TimetableResponse {
        let response = PreviewData.timetableResponse
        return term == .permanent ? response : response.rebased(toWeekContaining: weekStart)
    }
}
