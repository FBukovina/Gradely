import Foundation

protocol PlannerPersisting {
    func load() throws -> [PlannerItem]
    func save(_ items: [PlannerItem]) throws
}

/// Personal data, deliberately separate from expiring school caches and their logout cleanup.
/// Uses the same protected, atomic JSON/Application Support convention as the existing stores.
final class PlannerPersistence: PlannerPersisting {
    private let directory: URL?
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    private func fileURL() throws -> URL {
        let directory = try directory ?? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "Gradely", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "personal-planner.json")
    }

    func load() throws -> [PlannerItem] {
        let url = try fileURL()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: data)
        guard payload.version == 1, Set(payload.items.map(\.id)).count == payload.items.count else {
            throw PlannerError.storageUnavailable
        }
        return payload.items
    }

    func save(_ items: [PlannerItem]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Payload(version: 1, items: items))
        try data.write(to: fileURL(), options: [.atomic, .completeFileProtection])
    }

    private struct Payload: Codable {
        let version: Int
        let items: [PlannerItem]
    }
}

final class InMemoryPlannerPersistence: PlannerPersisting {
    var items: [PlannerItem]
    init(items: [PlannerItem] = []) { self.items = items }
    func load() throws -> [PlannerItem] { items }
    func save(_ items: [PlannerItem]) throws { self.items = items }
}
