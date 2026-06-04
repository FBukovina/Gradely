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

/// File-backed cache that keeps the most recently viewed week so the tab can render instantly
/// (and offline) before the network refresh lands. Mirrors `MarksCache`.
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
        let data = try Data(contentsOf: fileURL)
        let payload = try decoder.decode(Payload.self, from: data)
        guard payload.weekStartKey == Self.key(for: weekStart) else { return nil }
        return CachedTimetable(response: payload.response, weekStart: payload.weekStart, cachedAt: payload.cachedAt)
    }

    func save(_ response: TimetableResponse, weekStart: Date) throws {
        let payload = Payload(
            response: response,
            weekStart: weekStart,
            weekStartKey: Self.key(for: weekStart),
            cachedAt: Date()
        )
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
        let response: TimetableResponse
        let weekStart: Date
        let weekStartKey: String
        let cachedAt: Date
    }
}

final class InMemoryTimetableCache: TimetableCaching {
    private(set) var cached: CachedTimetable?

    init(cached: CachedTimetable? = nil) {
        self.cached = cached
    }

    func load(weekStart: Date) throws -> CachedTimetable? {
        guard
            let cached,
            TimetableDates.apiDateString(cached.weekStart) == TimetableDates.apiDateString(weekStart)
        else {
            return nil
        }
        return cached
    }

    func save(_ response: TimetableResponse, weekStart: Date) throws {
        cached = CachedTimetable(response: response, weekStart: weekStart, cachedAt: Date())
    }

    func clear() throws {
        cached = nil
    }
}
