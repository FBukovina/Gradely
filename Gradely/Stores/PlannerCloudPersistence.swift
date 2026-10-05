import Foundation

struct PlannerCloudState: Codable {
    var version = 1
    var items: [PlannerItem] = []
    var revisions: [String: Int64] = [:]
    var pending: [PlannerCloudChange] = []
    var conflicts: [PlannerCloudConflict] = []
    var cursor: Int64 = 0
    var importedLegacyIDs: Set<UUID> = []
}

protocol PlannerCloudPersisting {
    func load(owner: String) throws -> PlannerCloudState
    func save(_ state: PlannerCloudState, owner: String) throws
}

final class PlannerCloudPersistence: PlannerCloudPersisting {
    private let directory: URL?
    init(directory: URL? = nil) { self.directory = directory }
    private func url(owner: String) throws -> URL {
        guard let id = UUID(uuidString: owner) else { throw PlannerError.storageUnavailable }
        let directory = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "Gradely/PlannerAccounts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: id.uuidString.lowercased() + ".json")
    }
    func load(owner: String) throws -> PlannerCloudState {
        let data: Data
        do { data = try Data(contentsOf: url(owner: owner)) }
        catch CocoaError.fileReadNoSuchFile { return PlannerCloudState() }
        let state = try PlannerCloudCoding.decoder().decode(PlannerCloudState.self, from: data)
        guard state.version == 1, Set(state.items.map(\.id)).count == state.items.count else { throw PlannerError.storageUnavailable }
        return state
    }
    func save(_ state: PlannerCloudState, owner: String) throws {
        try PlannerCloudCoding.encoder().encode(state).write(to: url(owner: owner), options: [.atomic, .completeFileProtection])
    }
}

final class InMemoryPlannerCloudPersistence: PlannerCloudPersisting {
    var states: [String: PlannerCloudState] = [:]
    func load(owner: String) throws -> PlannerCloudState { states[owner] ?? PlannerCloudState() }
    func save(_ state: PlannerCloudState, owner: String) throws { states[owner] = state }
}
