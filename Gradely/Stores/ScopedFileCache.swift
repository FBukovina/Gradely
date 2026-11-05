import Foundation

struct CachedValue<Value> {
    let value: Value
    let cachedAt: Date
}

/// The last copy of one Bakaláři payload per school account, for offline
/// display. Without a directory it only keeps values in memory (demo, previews).
final class ScopedFileCache<Value: Codable> {
    private let prefix: String
    private let directory: URL?
    private var memory: [SchoolDataScope: CachedValue<Value>] = [:]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(prefix: String, directory: URL?) {
        self.prefix = prefix
        self.directory = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    static func inMemory(prefix: String) -> ScopedFileCache {
        ScopedFileCache(prefix: prefix, directory: nil)
    }

    /// Application Support/Gradely, next to the other school caches.
    static func onDisk(prefix: String, fileManager: FileManager = .default) -> ScopedFileCache {
        guard let directory = try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "Gradely", directoryHint: .isDirectory),
            (try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
        else { return inMemory(prefix: prefix) }
        return ScopedFileCache(prefix: prefix, directory: directory)
    }

    func load(scope: SchoolDataScope) -> CachedValue<Value>? {
        guard let fileURL = fileURL(for: scope) else { return memory[scope] }
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? decoder.decode(Payload.self, from: data) else { return nil }
        return CachedValue(value: payload.value, cachedAt: payload.cachedAt)
    }

    func save(_ value: Value, scope: SchoolDataScope) {
        let cachedAt = Date()
        guard let fileURL = fileURL(for: scope) else {
            memory[scope] = CachedValue(value: value, cachedAt: cachedAt)
            return
        }
        guard let data = try? encoder.encode(Payload(value: value, cachedAt: cachedAt)) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        memory = [:]
        guard let directory,
              let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for fileURL in contents where fileURL.lastPathComponent.hasPrefix(prefix + "-") {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func clear(scope: SchoolDataScope) {
        memory[scope] = nil
        guard let fileURL = fileURL(for: scope) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func fileURL(for scope: SchoolDataScope) -> URL? {
        directory?.appending(path: scope.filename(prefix: prefix))
    }

    private struct Payload: Codable {
        let value: Value
        let cachedAt: Date
    }
}
