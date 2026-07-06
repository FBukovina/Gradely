import Foundation

struct CachedAbsence: Equatable {
    let response: AbsenceResponse
    let cachedAt: Date
}

protocol AbsenceCaching {
    func load() throws -> CachedAbsence?
    func load(scope: SchoolDataScope) throws -> CachedAbsence?
    func save(_ response: AbsenceResponse) throws
    func save(_ response: AbsenceResponse, scope: SchoolDataScope) throws
    func clear() throws
    func clear(scope: SchoolDataScope) throws
}

final class AbsenceCache: AbsenceCaching {
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

    func load() throws -> CachedAbsence? {
        try load(from: legacyFileURL)
    }

    func load(scope: SchoolDataScope) throws -> CachedAbsence? {
        try load(from: fileURL(for: scope))
    }

    func save(_ response: AbsenceResponse) throws {
        try save(response, to: legacyFileURL)
    }

    func save(_ response: AbsenceResponse, scope: SchoolDataScope) throws {
        try save(response, to: fileURL(for: scope))
    }

    func clear() throws {
        try clear(legacyFileURL)
    }

    func clear(scope: SchoolDataScope) throws {
        try clear(fileURL(for: scope))
    }

    private var legacyFileURL: URL {
        directory.appending(path: "absence-cache.json")
    }

    private func fileURL(for scope: SchoolDataScope) -> URL {
        directory.appending(path: scope.filename(prefix: "absence-cache"))
    }

    private func load(from fileURL: URL) throws -> CachedAbsence? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let payload = try decoder.decode(Payload.self, from: data)
        return CachedAbsence(response: payload.response, cachedAt: payload.cachedAt)
    }

    private func save(_ response: AbsenceResponse, to fileURL: URL) throws {
        let payload = Payload(response: response, cachedAt: Date())
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func clear(_ fileURL: URL) throws {
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
    private var cachedAbsenceByScope: [SchoolDataScope: CachedAbsence]

    init(cachedAbsence: CachedAbsence? = nil) {
        self.cachedAbsence = cachedAbsence
        cachedAbsenceByScope = [:]
    }

    func load() throws -> CachedAbsence? {
        cachedAbsence
    }

    func load(scope: SchoolDataScope) throws -> CachedAbsence? {
        cachedAbsenceByScope[scope] ?? (cachedAbsenceByScope.isEmpty ? cachedAbsence : nil)
    }

    func save(_ response: AbsenceResponse) throws {
        cachedAbsence = CachedAbsence(response: response, cachedAt: Date())
    }

    func save(_ response: AbsenceResponse, scope: SchoolDataScope) throws {
        let saved = CachedAbsence(response: response, cachedAt: Date())
        cachedAbsence = saved
        cachedAbsenceByScope[scope] = saved
    }

    func clear() throws {
        cachedAbsence = nil
    }

    func clear(scope: SchoolDataScope) throws {
        cachedAbsenceByScope.removeValue(forKey: scope)
        if cachedAbsenceByScope.isEmpty {
            cachedAbsence = nil
        }
    }
}
