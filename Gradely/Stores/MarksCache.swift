import Foundation

struct CachedMarks: Equatable {
    let marksResponse: MarksResponse
    let cachedAt: Date
}

protocol MarksCaching {
    func load() throws -> CachedMarks?
    func load(scope: SchoolDataScope) throws -> CachedMarks?
    func save(_ marksResponse: MarksResponse) throws
    func save(_ marksResponse: MarksResponse, scope: SchoolDataScope) throws
    func clear() throws
    func clear(scope: SchoolDataScope) throws
}

final class MarksCache: MarksCaching {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) throws {
        directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appending(path: "Gradely", directoryHint: .isDirectory)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> CachedMarks? {
        try load(from: legacyFileURL)
    }

    func load(scope: SchoolDataScope) throws -> CachedMarks? {
        try load(from: fileURL(for: scope))
    }

    func save(_ marksResponse: MarksResponse) throws {
        try save(marksResponse, to: legacyFileURL)
    }

    func save(_ marksResponse: MarksResponse, scope: SchoolDataScope) throws {
        try save(marksResponse, to: fileURL(for: scope))
    }

    func clear() throws {
        try clear(legacyFileURL)
    }

    func clear(scope: SchoolDataScope) throws {
        try clear(fileURL(for: scope))
    }

    private var legacyFileURL: URL {
        directory.appending(path: "marks-cache.json")
    }

    private func fileURL(for scope: SchoolDataScope) -> URL {
        directory.appending(path: scope.filename(prefix: "marks-cache"))
    }

    private func load(from fileURL: URL) throws -> CachedMarks? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let payload = try decoder.decode(Payload.self, from: data)
        return CachedMarks(marksResponse: payload.marksResponse, cachedAt: payload.cachedAt)
    }

    private func save(_ marksResponse: MarksResponse, to fileURL: URL) throws {
        let payload = Payload(marksResponse: marksResponse, cachedAt: Date())
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func clear(_ fileURL: URL) throws {
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
    private var cachedMarksByScope: [SchoolDataScope: CachedMarks]

    init(cachedMarks: CachedMarks? = nil) {
        self.cachedMarks = cachedMarks
        cachedMarksByScope = [:]
    }

    func load() throws -> CachedMarks? {
        cachedMarks
    }

    func load(scope: SchoolDataScope) throws -> CachedMarks? {
        cachedMarksByScope[scope] ?? (cachedMarksByScope.isEmpty ? cachedMarks : nil)
    }

    func save(_ marksResponse: MarksResponse) throws {
        cachedMarks = CachedMarks(marksResponse: marksResponse, cachedAt: Date())
    }

    func save(_ marksResponse: MarksResponse, scope: SchoolDataScope) throws {
        let saved = CachedMarks(marksResponse: marksResponse, cachedAt: Date())
        cachedMarks = saved
        cachedMarksByScope[scope] = saved
    }

    func clear() throws {
        cachedMarks = nil
    }

    func clear(scope: SchoolDataScope) throws {
        cachedMarksByScope.removeValue(forKey: scope)
        if cachedMarksByScope.isEmpty {
            cachedMarks = nil
        }
    }
}
