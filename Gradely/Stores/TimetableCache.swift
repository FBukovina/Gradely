import Foundation

struct CachedTimetable: Equatable {
    let response: TimetableResponse
    let weekStart: Date
    let cachedAt: Date
}

protocol TimetableCaching {
    /// Returns the cached week only if it matches the requested `weekStart`.
    func load(weekStart: Date) throws -> CachedTimetable?
    func save(_ response: TimetableResponse, weekStart: Date) throws
    func clear() throws
}

/// File-backed cache that keeps recently loaded weeks so the tab and absence fallback can render
/// instantly (and offline) before the network refresh lands. Mirrors `MarksCache`.
final class TimetableCache: TimetableCaching {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) throws {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appending(path: "Gradely", directoryHint: .isDirectory)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        fileURL = directory.appending(path: "timetable-cache.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(weekStart: Date) throws -> CachedTimetable? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try loadEntries()[Self.key(for: weekStart)]
    }

    func save(_ response: TimetableResponse, weekStart: Date) throws {
        var entries = (try? loadEntries()) ?? [:]
        let weekStartKey = Self.key(for: weekStart)
        entries[weekStartKey] = CachedTimetable(response: response, weekStart: weekStart, cachedAt: Date())

        let payload = Payload(entries: entries.map { key, value in
            Payload.Entry(
                weekStartKey: key,
                response: value.response,
                weekStart: value.weekStart,
                cachedAt: value.cachedAt
            )
        })
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func key(for weekStart: Date) -> String {
        TimetableDates.apiDateString(weekStart)
    }

    private struct Payload: Codable {
        let entries: [Entry]

        struct Entry: Codable {
            let weekStartKey: String
            let response: TimetableResponse
            let weekStart: Date
            let cachedAt: Date
        }
    }

    private struct LegacyPayload: Codable {
        let response: TimetableResponse
        let weekStart: Date
        let weekStartKey: String
        let cachedAt: Date
    }

    private func loadEntries() throws -> [String: CachedTimetable] {
        let data = try Data(contentsOf: fileURL)

        if let payload = try? decoder.decode(Payload.self, from: data) {
            return Dictionary(
                payload.entries.map { entry in
                    (
                        entry.weekStartKey,
                        CachedTimetable(
                            response: entry.response,
                            weekStart: entry.weekStart,
                            cachedAt: entry.cachedAt
                        )
                    )
                },
                uniquingKeysWith: { first, _ in first }
            )
        }

        let legacy = try decoder.decode(LegacyPayload.self, from: data)
        return [
            legacy.weekStartKey: CachedTimetable(
                response: legacy.response,
                weekStart: legacy.weekStart,
                cachedAt: legacy.cachedAt
            )
        ]
    }
}

final class InMemoryTimetableCache: TimetableCaching {
    private(set) var cached: CachedTimetable?
    private var cachedByWeek: [String: CachedTimetable]

    init(cached: CachedTimetable? = nil) {
        self.cached = cached
        if let cached {
            cachedByWeek = [TimetableDates.apiDateString(cached.weekStart): cached]
        } else {
            cachedByWeek = [:]
        }
    }

    func load(weekStart: Date) throws -> CachedTimetable? {
        cachedByWeek[TimetableDates.apiDateString(weekStart)]
    }

    func save(_ response: TimetableResponse, weekStart: Date) throws {
        let saved = CachedTimetable(response: response, weekStart: weekStart, cachedAt: Date())
        cached = saved
        cachedByWeek[TimetableDates.apiDateString(weekStart)] = saved
    }

    func clear() throws {
        cached = nil
        cachedByWeek = [:]
    }
}
