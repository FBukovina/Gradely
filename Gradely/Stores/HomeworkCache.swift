import Foundation

protocol HomeworkCaching {
    func load(scope: SchoolDataScope) throws -> CachedHomework?
    func save(_ response: HomeworkResponse, scope: SchoolDataScope) throws
    func clear() throws
    func clear(scope: SchoolDataScope) throws
}

/// The last homework list per school account, for offline display.
final class HomeworkCache: HomeworkCaching {
    private static let prefix = "homework-cache"
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

    func load(scope: SchoolDataScope) throws -> CachedHomework? {
        let fileURL = fileURL(for: scope)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let payload = try decoder.decode(Payload.self, from: Data(contentsOf: fileURL))
        return CachedHomework(response: payload.response, cachedAt: payload.cachedAt)
    }

    func save(_ response: HomeworkResponse, scope: SchoolDataScope) throws {
        let data = try encoder.encode(Payload(response: response, cachedAt: Date()))
        try data.write(to: fileURL(for: scope), options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for fileURL in contents where fileURL.lastPathComponent.hasPrefix(Self.prefix) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func clear(scope: SchoolDataScope) throws {
        let fileURL = fileURL(for: scope)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func fileURL(for scope: SchoolDataScope) -> URL {
        directory.appending(path: scope.filename(prefix: Self.prefix))
    }

    private struct Payload: Codable {
        let response: HomeworkResponse
        let cachedAt: Date
    }
}

final class InMemoryHomeworkCache: HomeworkCaching {
    private var cached: [SchoolDataScope: CachedHomework] = [:]

    func load(scope: SchoolDataScope) throws -> CachedHomework? { cached[scope] }

    func save(_ response: HomeworkResponse, scope: SchoolDataScope) throws {
        cached[scope] = CachedHomework(response: response, cachedAt: Date())
    }

    func clear() throws { cached = [:] }

    func clear(scope: SchoolDataScope) throws { cached[scope] = nil }
}
