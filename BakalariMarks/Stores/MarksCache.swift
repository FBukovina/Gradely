import Foundation

struct CachedMarks: Equatable {
    let marksResponse: MarksResponse
    let cachedAt: Date
}

protocol MarksCaching {
    func load() throws -> CachedMarks?
    func save(_ marksResponse: MarksResponse) throws
    func clear() throws
}

final class MarksCache: MarksCaching {
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
        .appending(path: "BakalariMarks", directoryHint: .isDirectory)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        fileURL = directory.appending(path: "marks-cache.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> CachedMarks? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let payload = try decoder.decode(Payload.self, from: data)
        return CachedMarks(marksResponse: payload.marksResponse, cachedAt: payload.cachedAt)
    }

    func save(_ marksResponse: MarksResponse) throws {
        let payload = Payload(marksResponse: marksResponse, cachedAt: Date())
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private struct Payload: Codable {
        let marksResponse: MarksResponse
        let cachedAt: Date
    }
}

final class InMemoryMarksCache: MarksCaching {
    private(set) var cachedMarks: CachedMarks?

    init(cachedMarks: CachedMarks? = nil) {
        self.cachedMarks = cachedMarks
    }

    func load() throws -> CachedMarks? {
        cachedMarks
    }

    func save(_ marksResponse: MarksResponse) throws {
        cachedMarks = CachedMarks(marksResponse: marksResponse, cachedAt: Date())
    }

    func clear() throws {
        cachedMarks = nil
    }
}
