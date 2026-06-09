import Foundation

struct CachedStravaCZMenu: Codable, Equatable {
    let menu: StravaCZMenu
    let cachedAt: Date
}

protocol StravaCZMenuCaching {
    func load() throws -> CachedStravaCZMenu?
    func save(_ menu: StravaCZMenu) throws
    func clear() throws
}

final class StravaCZMenuCache: StravaCZMenuCaching {
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

        fileURL = directory.appending(path: "stravacz-menu-cache.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> CachedStravaCZMenu? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(CachedStravaCZMenu.self, from: data)
    }

    func save(_ menu: StravaCZMenu) throws {
        let data = try encoder.encode(CachedStravaCZMenu(menu: menu, cachedAt: Date()))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

final class InMemoryStravaCZMenuCache: StravaCZMenuCaching {
    private(set) var cachedMenu: CachedStravaCZMenu?

    init(cachedMenu: CachedStravaCZMenu? = nil) {
        self.cachedMenu = cachedMenu
    }

    func load() throws -> CachedStravaCZMenu? {
        cachedMenu
    }

    func save(_ menu: StravaCZMenu) throws {
        cachedMenu = CachedStravaCZMenu(menu: menu, cachedAt: Date())
    }

    func clear() throws {
        cachedMenu = nil
    }
}
