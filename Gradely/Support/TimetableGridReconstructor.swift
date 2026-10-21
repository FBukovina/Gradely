import CoreGraphics
import Foundation

/// One piece of text read from a timetable PDF or photo, in page coordinates
/// with the origin at the top left.
nonisolated struct TimetableTextRun: Equatable, Sendable {
    var text: String
    var frame: CGRect
    /// Point size from the PDF, or the glyph height when the text came from OCR.
    var fontSize: CGFloat
}

/// A timetable read from a document, still editable before it is saved.
nonisolated struct ImportedTimetableDraft: Equatable, Sendable {
    struct Hour: Equatable, Hashable, Identifiable, Sendable {
        var id: Int
        var caption: String
        var beginTime: String
        var endTime: String
    }

    struct Lesson: Equatable, Identifiable, Sendable {
        var id = UUID()
        /// 1 = Monday … 7 = Sunday, like the Bakaláři API.
        var dayOfWeek: Int
        var hourID: Int
        var subject: String
        var room: String = ""
        var teacher: String = ""
        var group: String = ""
    }

    var hours: [Hour]
    var lessons: [Lesson]

    var groups: [String] {
        Array(Set(lessons.map(\.group).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The usual Czech lesson times, for a timetable typed in by hand.
    static var blank: ImportedTimetableDraft {
        let times = [
            ("8:00", "8:45"), ("8:55", "9:40"), ("10:00", "10:45"), ("10:55", "11:40"), ("11:50", "12:35"),
            ("12:45", "13:30"), ("13:40", "14:25"), ("14:35", "15:20"), ("15:30", "16:15")
        ]
        return ImportedTimetableDraft(
            hours: times.enumerated().map { Hour(id: $0.offset + 1, caption: "\($0.offset + 1)", beginTime: $0.element.0, endTime: $0.element.1) },
            lessons: []
        )
    }

    /// The draft as a permanent (weekday-only) Bakaláři payload, so the regular
    /// timetable mapper and screens can show it.
    @MainActor func makeResponse(excludingGroups excluded: Set<String> = []) -> TimetableResponse {
        let kept = lessons.filter { !$0.subject.trimmed.isEmpty && ($0.group.isEmpty || !excluded.contains($0.group)) }
        var subjects: [String: TimetableEntity] = [:]
        var teachers: [String: TimetableEntity] = [:]
        var rooms: [String: TimetableEntity] = [:]
        var groups: [String: TimetableGroup] = [:]

        func entityID(_ prefix: String, _ value: String) -> String? {
            let value = value.trimmed
            return value.isEmpty ? nil : "\(prefix)-\(value)"
        }

        let hourOrder = Dictionary(uniqueKeysWithValues: hours.enumerated().map { ($0.element.id, $0.offset) })
        let lastDay = max(5, kept.map(\.dayOfWeek).max() ?? 5)
        let days = (1...lastDay).map { dayOfWeek -> TimetableDayDTO in
            let atoms = kept
                .filter { $0.dayOfWeek == dayOfWeek }
                .sorted { (hourOrder[$0.hourID] ?? .max) < (hourOrder[$1.hourID] ?? .max) }
                .map { lesson -> TimetableAtom in
                    let subjectID = entityID("s", lesson.subject)
                    if let subjectID { subjects[subjectID] = TimetableEntity(id: subjectID, abbrev: lesson.subject.trimmed, name: lesson.subject.trimmed) }
                    let teacherID = entityID("t", lesson.teacher)
                    if let teacherID { teachers[teacherID] = TimetableEntity(id: teacherID, abbrev: lesson.teacher.trimmed, name: lesson.teacher.trimmed) }
                    let roomID = entityID("r", lesson.room)
                    if let roomID { rooms[roomID] = TimetableEntity(id: roomID, abbrev: lesson.room.trimmed, name: lesson.room.trimmed) }
                    let groupID = entityID("g", lesson.group)
                    if let groupID { groups[groupID] = TimetableGroup(id: groupID, abbrev: lesson.group.trimmed, name: lesson.group.trimmed) }
                    return TimetableAtom(
                        hourID: lesson.hourID,
                        groupIDs: groupID.map { [$0] } ?? [],
                        subjectID: subjectID,
                        teacherID: teacherID,
                        roomID: roomID
                    )
                }
            return TimetableDayDTO(atoms: atoms, dayOfWeek: dayOfWeek, date: "")
        }

        return TimetableResponse(
            hours: hours.map { TimetableHour(id: $0.id, caption: $0.caption, beginTime: $0.beginTime, endTime: $0.endTime) },
            days: days,
            groups: groups.values.sorted { $0.id < $1.id },
            subjects: subjects.values.sorted { $0.id < $1.id },
            teachers: teachers.values.sorted { $0.id < $1.id },
            rooms: rooms.values.sorted { $0.id < $1.id }
        )
    }
}

/// Rebuilds a day × lesson grid from positioned text: finds the weekday labels,
/// the lesson columns from the header times and numbers, then sorts the
/// remaining text into cells. Bakaláři prints each lesson as group (top left),
/// room (top right), subject (large, centred) and teacher (below); aSc exports
/// are close to that.
nonisolated enum TimetableGridReconstructor {
    /// - Parameter sizesAreReliable: true for a PDF text layer. OCR heights are
    ///   too noisy to tell the subject by size, so cells are read by layout instead.
    static func reconstruct(_ input: [TimetableTextRun], sizesAreReliable: Bool = true) -> ImportedTimetableDraft? {
        let runs = input.compactMap { run -> TimetableTextRun? in
            var run = run
            run.text = cleaned(run.text)
            return run.text.isEmpty || run.frame.width <= 0 || run.frame.height <= 0 ? nil : run
        }
        guard let labels = dayLabels(in: runs) else { return nil }

        // Work as if days were rows; a timetable with days as columns is transposed.
        let oriented = labels.daysAreRows ? runs : runs.map(\.transposed)
        let dayRuns = labels.daysAreRows ? labels.runs : labels.runs.map { ($0.weekday, $0.run.transposed) }
        let labelRight = dayRuns.map(\.1.frame.maxX).max() ?? 0
        let firstLabelTop = dayRuns.map(\.1.frame.minY).min() ?? 0

        guard let header = header(in: oriented, rightOf: labelRight, above: firstLabelTop + (dayRuns.first?.1.frame.height ?? 0)),
              header.centers.count >= 2
        else { return nil }

        let columnBounds = bands(for: header.centers)
        let gridLeft = columnBounds.first?.lowerBound ?? labelRight
        let rowBounds = rowBands(
            labels: dayRuns.map(\.1),
            in: oriented.filter { $0.frame.midY > header.bottom },
            gridLeft: gridLeft,
            top: header.bottom
        )

        // Sort every remaining run into its (day, column) cell.
        var cells: [CellKey: [TimetableTextRun]] = [:]
        for run in oriented where !header.runs.contains(run) && !dayRuns.contains(where: { $0.1 == run }) {
            let point = CGPoint(x: run.frame.midX, y: run.frame.midY)
            guard point.x >= gridLeft, point.y > header.bottom,
                  let row = rowBounds.firstIndex(where: { $0.contains(point.y) }),
                  let column = columnBounds.firstIndex(where: { $0.contains(point.x) })
            else { continue }
            cells[CellKey(row: row, column: column), default: []].append(run)
        }

        var lessons: [ImportedTimetableDraft.Lesson] = []
        for (key, cellRuns) in cells.sorted(by: { ($0.key.row, $0.key.column) < ($1.key.row, $1.key.column) }) {
            let column = columnBounds[key.column]
            let entries = sizesAreReliable
                ? entriesBySize(in: cellRuns)
                : entriesByLayout(in: cellRuns, center: header.centers[key.column], width: column.upperBound - column.lowerBound)
            for entry in entries {
                lessons.append(ImportedTimetableDraft.Lesson(
                    dayOfWeek: dayRuns[key.row].0, hourID: key.column + 1,
                    subject: entry.subject, room: entry.room, teacher: entry.teacher, group: entry.group
                ))
            }
        }
        guard !lessons.isEmpty else { return nil }

        let hours = header.centers.indices.map { index in
            ImportedTimetableDraft.Hour(
                id: index + 1,
                caption: header.captions[index] ?? "\(index + 1)",
                beginTime: header.times[index]?.0 ?? "",
                endTime: header.times[index]?.1 ?? ""
            )
        }
        return ImportedTimetableDraft(hours: hours, lessons: lessons)
    }

    /// A short name for a page, such as the class ("1.A4"): the largest text above the grid.
    static func title(of runs: [TimetableTextRun]) -> String? {
        let labelsTop = dayLabels(in: runs).map { labels in
            labels.runs.map { labels.daysAreRows ? $0.run.frame.minY : $0.run.frame.minX }.min() ?? .greatestFiniteMagnitude
        } ?? .greatestFiniteMagnitude
        return runs
            .filter { $0.frame.maxY < labelsTop && $0.text.trimmed.count <= 24 }
            .max { $0.fontSize < $1.fontSize }?
            .text.trimmed
    }

    /// Drops the box borders OCR reads as brackets or bars around a label
    /// ("[NJ]", "INJI") and swaps Cyrillic look-alikes OCR sometimes returns ("Вi").
    private static func cleaned(_ text: String) -> String {
        var value = String(text.map { cyrillicLookalikes[$0] ?? $0 })
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|[]{}()")))
        if value.count >= 3, value.count <= 6, let first = value.first, let last = value.last,
           "Il".contains(first), "Il".contains(last), value.dropFirst().dropLast().allSatisfy({ $0.isUppercase || $0.isNumber }) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static let cyrillicLookalikes: [Character: Character] = [
        "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X",
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "і": "i"
    ]

    // MARK: - Weekday labels

    static func weekday(for text: String) -> Int? {
        let token = text.trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "," || $0 == ":" })
            .first.map(String.init) ?? ""
        return weekdayNames[token]
    }

    private static let weekdayNames: [String: Int] = {
        let names: [Int: [String]] = [
            1: ["po", "pondeli", "pondelok", "mon", "monday"],
            2: ["ut", "utery", "utorok", "tue", "tues", "tuesday"],
            3: ["st", "streda", "wed", "wednesday"],
            4: ["ct", "ctvrtek", "stv", "stvrtok", "thu", "thur", "thurs", "thursday"],
            5: ["pa", "patek", "pi", "piatok", "fri", "friday"],
            6: ["so", "sobota", "sat", "saturday"],
            7: ["ne", "nedele", "nedela", "sun", "sunday"]
        ]
        var result: [String: Int] = [:]
        for (day, list) in names { list.forEach { result[$0] = day } }
        return result
    }()

    private struct DayLabels {
        var runs: [(weekday: Int, run: TimetableTextRun)]
        var daysAreRows: Bool
    }

    /// The weekday names that line up in one column (days as rows) or one row
    /// (days as columns), in weekday order. Three or more are needed.
    private static func dayLabels(in runs: [TimetableTextRun]) -> DayLabels? {
        let candidates = runs.compactMap { run in weekday(for: run.text).map { (weekday: $0, run: run) } }
        guard candidates.count >= 3 else { return nil }

        var best: DayLabels?
        for daysAreRows in [true, false] {
            for anchor in candidates {
                let tolerance = max(anchor.run.frame.height, anchor.run.frame.width / 2)
                let aligned = candidates
                    .filter {
                        abs((daysAreRows ? $0.run.frame.midX : $0.run.frame.midY) - (daysAreRows ? anchor.run.frame.midX : anchor.run.frame.midY)) <= tolerance
                    }
                    .sorted { daysAreRows ? $0.run.frame.midY < $1.run.frame.midY : $0.run.frame.midX < $1.run.frame.midX }

                // Keep the longest run of strictly increasing weekdays.
                var ordered: [(weekday: Int, run: TimetableTextRun)] = []
                for candidate in aligned where candidate.weekday > (ordered.last?.weekday ?? 0) {
                    ordered.append(candidate)
                }
                if ordered.count >= 3, ordered.count > (best?.runs.count ?? 0) {
                    best = DayLabels(runs: ordered, daysAreRows: daysAreRows)
                }
            }
        }
        return best
    }

    // MARK: - Header

    private struct Header {
        var centers: [CGFloat]
        var captions: [String?]
        var times: [(String, String)?]
        var runs: [TimetableTextRun]
        var bottom: CGFloat
    }

    private struct TimedLesson {
        var begin: String
        var end: String
        var frame: CGRect
        var runs: [TimetableTextRun]
    }

    /// The lesson columns above the first day. Times are the sturdier source
    /// (OCR often misses a lone "1"); the lesson numbers then only label them.
    private static func header(in runs: [TimetableTextRun], rightOf labelRight: CGFloat, above limit: CGFloat) -> Header? {
        let area = runs.filter { $0.frame.midY < limit && $0.frame.midX > labelRight }
        let numberLine = longestIncreasingLine(area.filter { lessonNumber($0.text) != nil }) ?? []
        let timed = timedLessons(in: area)

        let centers: [CGFloat]
        let captions: [String?]
        let times: [(String, String)?]
        var used: [TimetableTextRun]
        if timed.count >= 2, timed.count >= numberLine.count {
            centers = timed.map(\.frame.midX)
            times = timed.map { ($0.begin, $0.end) }
            let columns = bands(for: centers)
            var known: [Int: Int] = [:]
            for run in numberLine {
                if let column = columns.firstIndex(where: { $0.contains(run.frame.midX) }), let number = lessonNumber(run.text) {
                    known[column] = number
                }
            }
            // Count on from the nearest number that was read.
            captions = centers.indices.map { index in
                guard let nearest = known.keys.min(by: { abs($0 - index) < abs($1 - index) }), let number = known[nearest] else { return nil }
                return "\(number + index - nearest)"
            }
            used = timed.flatMap(\.runs) + numberLine
        } else if numberLine.count >= 2 {
            centers = numberLine.map(\.frame.midX)
            captions = numberLine.map { lessonNumber($0.text).map(String.init) }
            let columns = bands(for: centers)
            let matched = columns.map { column in timed.first { column.contains($0.frame.midX) } }
            times = matched.map { $0.map { ($0.begin, $0.end) } }
            used = numberLine + matched.compactMap { $0 }.flatMap(\.runs)
        } else {
            return nil
        }

        return Header(
            centers: centers,
            captions: captions,
            times: times,
            runs: used,
            bottom: used.map(\.frame.maxY).max() ?? limit
        )
    }

    /// Lessons from the header times: a range ("8:00 - 8:45") is one lesson;
    /// single times are paired in order, a pair 25–100 minutes apart being a
    /// lesson and a shorter gap a break.
    private static func timedLessons(in runs: [TimetableTextRun]) -> [TimedLesson] {
        var lessons = runs.compactMap { run in
            timeRange(run.text).map { TimedLesson(begin: $0.0, end: $0.1, frame: run.frame, runs: [run]) }
        }
        let singles = runs
            .compactMap { run in time(run.text).map { (minutes: minutes($0), text: $0, run: run) } }
            .sorted { $0.minutes < $1.minutes }
        var index = 0
        while index + 1 < singles.count {
            let begin = singles[index], end = singles[index + 1]
            if (25...100).contains(end.minutes - begin.minutes) {
                lessons.append(TimedLesson(begin: begin.text, end: end.text, frame: begin.run.frame.union(end.run.frame), runs: [begin.run, end.run]))
                index += 2
            } else {
                index += 1
            }
        }
        return lessons
            .sorted { $0.frame.midX < $1.frame.midX }
            .reduce(into: []) { result, lesson in
                if let last = result.last, last.frame.intersects(lesson.frame) { return }
                result.append(lesson)
            }
    }

    private static func minutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }

    private static func lessonNumber(_ text: String) -> Int? {
        var value = text.trimmed
        if value.hasSuffix(".") { value.removeLast() }
        guard value.count <= 2, let number = Int(value), (0...16).contains(number) else { return nil }
        return number
    }

    private static func time(_ text: String) -> String? {
        let value = text.trimmed
        guard let match = value.wholeMatch(of: /(\d{1,2})[:.](\d{2})/),
              let hour = Int(match.1), hour < 24, let minute = Int(match.2), minute < 60
        else { return nil }
        return String(format: "%d:%02d", hour, minute)
    }

    private static func timeRange(_ text: String) -> (String, String)? {
        let value = text.trimmed
        guard let match = value.wholeMatch(of: /(\d{1,2}[:.]\d{2})\s*[-\u{2013}\u{2014}]\s*(\d{1,2}[:.]\d{2})/),
              let begin = time(String(match.1)), let end = time(String(match.2))
        else { return nil }
        return (begin, end)
    }

    /// The largest set of numbers on one line whose values go up left to right.
    private static func longestIncreasingLine(_ runs: [TimetableTextRun]) -> [TimetableTextRun]? {
        var best: [TimetableTextRun]?
        for anchor in runs {
            let line = runs
                .filter { abs($0.frame.midY - anchor.frame.midY) <= anchor.frame.height / 2 }
                .sorted { $0.frame.midX < $1.frame.midX }
            var increasing: [TimetableTextRun] = []
            for run in line where (lessonNumber(run.text) ?? -1) > (increasing.last.flatMap { lessonNumber($0.text) } ?? -1) {
                increasing.append(run)
            }
            if increasing.count > (best?.count ?? 1) { best = increasing }
        }
        return best
    }

    /// Day rows differ in height (a row with a group split is twice as tall),
    /// so halfway between labels cuts into the taller row. Each label (with
    /// the date printed under it) sits in the middle of its row, which gives
    /// every next edge as 2 × centre − previous edge; that edge is then moved
    /// to the nearest empty strip between lines of text.
    private static func rowBands(labels: [TimetableTextRun], in runs: [TimetableTextRun], gridLeft: CGFloat, top: CGFloat) -> [Range<CGFloat>] {
        let labelColumn = runs.filter { $0.frame.midX < gridLeft && !labels.contains($0) }
        let centers = labels.map { label in
            labelColumn
                .filter { abs($0.frame.midY - label.frame.midY) < label.frame.height * 2 }
                .reduce(label.frame) { $0.union($1.frame) }
                .midY
        }
        let content = runs.filter { $0.frame.midX >= gridLeft }

        var edges = [top]
        for index in centers.indices {
            let estimate = 2 * centers[index] - edges[index]
            guard index + 1 < centers.count else {
                edges.append(max(estimate, labels[index].frame.maxY))
                break
            }
            let low = centers[index], high = centers[index + 1]
            let target = min(max(estimate, low), high)
            var gaps: [CGFloat] = []
            var reach = low
            for span in content.map(\.frame).filter({ $0.midY > low && $0.midY < high }).sorted(by: { $0.minY < $1.minY }) {
                if span.minY > reach { gaps.append((reach + span.minY) / 2) }
                reach = max(reach, span.maxY)
            }
            if high > reach { gaps.append((reach + high) / 2) }
            edges.append(gaps.min { abs($0 - target) < abs($1 - target) } ?? target)
        }

        guard zip(edges, edges.dropFirst()).allSatisfy({ $0 < $1 }) else {
            // Labels that don't sit mid-row: fall back to halfway splits.
            var halfway = bands(for: labels.map(\.frame.midY))
            halfway[0] = max(halfway[0].lowerBound, top)..<max(halfway[0].upperBound, top)
            return halfway
        }
        return zip(edges, edges.dropFirst()).map { $0..<$1 }
    }

    /// Splits the axis halfway between neighbouring centres; the outer bands
    /// extend by half the neighbouring gap.
    private static func bands(for centers: [CGFloat]) -> [Range<CGFloat>] {
        guard centers.count >= 2 else {
            return centers.map { ($0 - 1_000)..<($0 + 1_000) }
        }
        return centers.indices.map { index in
            let previousGap = index > 0 ? centers[index] - centers[index - 1] : centers[1] - centers[0]
            let nextGap = index < centers.count - 1 ? centers[index + 1] - centers[index] : previousGap
            return (centers[index] - previousGap / 2)..<(centers[index] + nextGap / 2)
        }
    }

    // MARK: - Cells

    private struct CellKey: Hashable {
        let row: Int
        let column: Int
    }

    private struct Entry {
        var subject: String
        var room = ""
        var teacher = ""
        var group = ""
    }

    /// One cell can hold several lessons (groups split the class). Each lesson
    /// is anchored on its subject, the largest text in the cell.
    private static func entriesBySize(in runs: [TimetableTextRun]) -> [Entry] {
        guard let largest = runs.map(\.fontSize).max() else { return [] }
        let smallest = runs.map(\.fontSize).min() ?? largest
        guard largest > smallest * 1.15 else {
            let center = runs.map(\.frame.midX).reduce(0, +) / CGFloat(runs.count)
            let width = (runs.map(\.frame.maxX).max() ?? 0) - (runs.map(\.frame.minX).min() ?? 0)
            return entriesByLayout(in: runs, center: center, width: max(width, 1))
        }
        let anchors = runs
            .filter { $0.fontSize >= largest * 0.85 }
            .sorted { ($0.frame.midY, $0.frame.midX) < ($1.frame.midY, $1.frame.midX) }

        // A lone letter next to a lesson is a change badge (S, M, N), not a teacher.
        var parts: [[TimetableTextRun]] = Array(repeating: [], count: anchors.count)
        for run in runs where !anchors.contains(run) && run.text.trimmed.count > 1 {
            let nearest = anchors.indices.min {
                distance(run.frame, anchors[$0].frame) < distance(run.frame, anchors[$1].frame)
            } ?? 0
            parts[nearest].append(run)
        }

        return anchors.indices.map { index in
            let anchor = anchors[index].frame
            var entry = Entry(subject: anchors[index].text.trimmed)
            let above = parts[index].filter { $0.frame.midY < anchor.minY }.sorted { $0.frame.midX < $1.frame.midX }
            let below = parts[index].filter { $0.frame.midY > anchor.maxY }.sorted { $0.frame.midX < $1.frame.midX }
            let beside = parts[index].filter { $0.frame.midY >= anchor.minY && $0.frame.midY <= anchor.maxY }

            if above.count >= 2 {
                entry.group = above.dropLast().map(\.text.trimmed).joined(separator: " ")
                entry.room = above.last!.text.trimmed
            } else if let only = above.first {
                if only.frame.midX > anchor.midX { entry.room = only.text.trimmed } else { entry.group = only.text.trimmed }
            }
            if below.count >= 2, entry.room.isEmpty {
                entry.teacher = below.dropLast().map(\.text.trimmed).joined(separator: " ")
                entry.room = below.last!.text.trimmed
            } else if !below.isEmpty {
                entry.teacher = below.map(\.text.trimmed).joined(separator: " ")
            }
            // Beside the subject only a missing room or group is filled in;
            // anything else there is a badge ("S" for a substitution).
            for run in beside {
                if run.frame.midX > anchor.maxX, entry.room.isEmpty {
                    entry.room = run.text.trimmed
                } else if run.frame.midX < anchor.minX, entry.group.isEmpty {
                    entry.group = run.text.trimmed
                }
            }
            return entry
        }
    }

    /// Reads a cell line by line: a line with text only at the edges (group
    /// left, room right) starts a lesson; centred lines are its subject, then
    /// its teacher.
    private static func entriesByLayout(in runs: [TimetableTextRun], center: CGFloat, width: CGFloat) -> [Entry] {
        var lines: [[TimetableTextRun]] = []
        for run in runs.sorted(by: { $0.frame.midY < $1.frame.midY }) {
            if let last = lines.indices.last,
               abs(lines[last][0].frame.midY - run.frame.midY) <= min(lines[last][0].frame.height, run.frame.height) / 2 {
                lines[last].append(run)
            } else {
                lines.append([run])
            }
        }

        var entries: [Entry] = []
        var current: Entry?
        var hasTeacher = false
        func finish() {
            if let entry = current, !entry.subject.isEmpty { entries.append(entry) }
            current = nil
            hasTeacher = false
        }

        for line in lines {
            let centred = line.filter { abs($0.frame.midX - center) < width * 0.2 }
            let edges = line.filter { !centred.contains($0) }
            if centred.isEmpty || (current?.subject.isEmpty == false && hasTeacher) {
                finish()
                current = Entry(subject: "")
            }
            for run in edges {
                if run.frame.midX > center, current?.room.isEmpty == true {
                    current?.room = run.text
                } else if run.frame.midX <= center, current?.group.isEmpty == true {
                    current?.group = run.text
                }
            }
            for run in centred.sorted(by: { $0.frame.midX < $1.frame.midX }) {
                if current == nil { current = Entry(subject: "") }
                if current?.subject.isEmpty == true {
                    current?.subject = run.text
                } else if !hasTeacher {
                    current?.teacher = run.text
                    hasTeacher = true
                }
            }
        }
        finish()
        return entries
    }

    private static func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
    }
}

nonisolated private extension TimetableTextRun {
    var transposed: TimetableTextRun {
        TimetableTextRun(
            text: text,
            frame: CGRect(x: frame.minY, y: frame.minX, width: frame.height, height: frame.width),
            fontSize: fontSize
        )
    }
}

nonisolated private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
