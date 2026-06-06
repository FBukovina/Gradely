import Foundation

struct CachedAbsence: Equatable {
    let response: AbsenceResponse
    let cachedAt: Date
}

protocol AbsenceCaching {
    func load() throws -> CachedAbsence?
    func save(_ response: AbsenceResponse) throws
    func clear() throws
}

final class AbsenceCache: AbsenceCaching {
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

        fileURL = directory.appending(path: "absence-cache.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> CachedAbsence? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let payload = try decoder.decode(Payload.self, from: data)
        return CachedAbsence(response: payload.response, cachedAt: payload.cachedAt)
    }

    func save(_ response: AbsenceResponse) throws {
        let payload = Payload(response: response, cachedAt: Date())
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private struct Payload: Codable {
        let response: AbsenceResponse
        let cachedAt: Date
    }
}

final class InMemoryAbsenceCache: AbsenceCaching {
    private(set) var cachedAbsence: CachedAbsence?

    init(cachedAbsence: CachedAbsence? = nil) {
        self.cachedAbsence = cachedAbsence
    }

    func load() throws -> CachedAbsence? {
        cachedAbsence
    }

    func save(_ response: AbsenceResponse) throws {
        cachedAbsence = CachedAbsence(response: response, cachedAt: Date())
    }

    func clear() throws {
        cachedAbsence = nil
    }
}
