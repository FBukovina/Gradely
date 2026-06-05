import Foundation

protocol SchoolDirectoryCaching {
    func load() throws -> CachedSchoolDirectory?
    func save(_ schools: [SchoolDirectorySchool], cachedAt: Date) throws
    func clear() throws
}

extension SchoolDirectoryCaching {
    func save(_ schools: [SchoolDirectorySchool]) throws {
        try save(schools, cachedAt: Date())
    }
}

final class SchoolDirectoryCache: SchoolDirectoryCaching {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, directory: URL? = nil) throws {
        self.fileManager = fileManager

        let cacheDirectory: URL
        if let directory {
            cacheDirectory = directory
        } else {
            cacheDirectory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: "Gradely", directoryHint: .isDirectory)
        }

        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        fileURL = cacheDirectory.appending(path: "school-directory-cache.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> CachedSchoolDirectory? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(CachedSchoolDirectory.self, from: data)
    }

    func save(_ schools: [SchoolDirectorySchool], cachedAt: Date = Date()) throws {
        let payload = CachedSchoolDirectory(schools: schools, cachedAt: cachedAt)
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

final class InMemorySchoolDirectoryCache: SchoolDirectoryCaching {
    private(set) var cachedDirectory: CachedSchoolDirectory?

    init(cachedDirectory: CachedSchoolDirectory? = nil) {
        self.cachedDirectory = cachedDirectory
    }

    func load() throws -> CachedSchoolDirectory? {
        cachedDirectory
    }

    func save(_ schools: [SchoolDirectorySchool], cachedAt: Date = Date()) throws {
        cachedDirectory = CachedSchoolDirectory(schools: schools, cachedAt: cachedAt)
    }

    func clear() throws {
        cachedDirectory = nil
    }
}
