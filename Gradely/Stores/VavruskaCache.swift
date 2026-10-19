import Foundation

protocol VavruskaCaching {
    func load() throws -> VavruskaSnapshot?
    func save(_ snapshot: VavruskaSnapshot) throws
    func clear() throws
}

final class VavruskaCache: VavruskaCaching {
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

        fileURL = directory.appending(path: "vavruska-cache.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> VavruskaSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(VavruskaSnapshot.self, from: Data(contentsOf: fileURL))
    }

    func save(_ snapshot: VavruskaSnapshot) throws {
        try encoder.encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

final class InMemoryVavruskaCache: VavruskaCaching {
    private var snapshot: VavruskaSnapshot?

    init(snapshot: VavruskaSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() throws -> VavruskaSnapshot? { snapshot }
    func save(_ snapshot: VavruskaSnapshot) throws { self.snapshot = snapshot }
    func clear() throws { snapshot = nil }
}
