import Foundation
import GradelyWatchShared

final class WatchTimetableCache {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        fileURL = GradelyWatchAppGroup.timetableCacheURL(fileManager: fileManager)
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> GradelyWatchTimetable? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try GradelyWatchSyncCodec.decoder.decode(GradelyWatchTimetable.self, from: data)
    }

    func save(_ timetable: GradelyWatchTimetable) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try GradelyWatchSyncCodec.encoder.encode(timetable)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }
}
