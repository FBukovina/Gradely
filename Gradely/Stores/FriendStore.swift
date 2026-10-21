import Foundation

protocol FriendStoring {
    func loadFriends() -> [Friend]
    func saveFriends(_ friends: [Friend]) throws
    func loadSession(friendID: UUID) -> StoredSession?
    func saveSession(_ session: StoredSession, friendID: UUID) throws
    func loadImportedTimetable(friendID: UUID) -> TimetableResponse?
    func saveImportedTimetable(_ response: TimetableResponse, friendID: UUID) throws
    func removeData(friendID: UUID)
}

/// The friend list in UserDefaults, each friend's Bakaláři session in the
/// Keychain (device-only, like your own), imported timetables as files.
final class FriendStore: FriendStoring {
    private let userDefaults: UserDefaults
    private let keychain: KeychainClient
    private let directory: URL
    private let key = "gradey.friends.v1"

    init(
        userDefaults: UserDefaults = .standard,
        keychain: KeychainClient = .live(),
        fileManager: FileManager = .default
    ) throws {
        self.userDefaults = userDefaults
        self.keychain = keychain
        directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Gradely/Friends", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadFriends() -> [Friend] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder.sessionDecoder.decode([Friend].self, from: data)) ?? []
    }

    func saveFriends(_ friends: [Friend]) throws {
        userDefaults.set(try JSONEncoder.sessionEncoder.encode(friends), forKey: key)
    }

    func loadSession(friendID: UUID) -> StoredSession? {
        guard let data = try? keychain.read(account: account(friendID)) else { return nil }
        return try? JSONDecoder.sessionDecoder.decode(StoredSession.self, from: data)
    }

    func saveSession(_ session: StoredSession, friendID: UUID) throws {
        try keychain.save(JSONEncoder.sessionEncoder.encode(session), account: account(friendID))
    }

    func loadImportedTimetable(friendID: UUID) -> TimetableResponse? {
        guard let data = try? Data(contentsOf: fileURL(friendID)) else { return nil }
        return try? JSONDecoder().decode(TimetableResponse.self, from: data)
    }

    func saveImportedTimetable(_ response: TimetableResponse, friendID: UUID) throws {
        try JSONEncoder().encode(response).write(to: fileURL(friendID), options: .atomic)
    }

    func removeData(friendID: UUID) {
        try? keychain.delete(account: account(friendID))
        try? FileManager.default.removeItem(at: fileURL(friendID))
    }

    private func account(_ id: UUID) -> String {
        "gradey.friend.\(id.uuidString).session"
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}

final class InMemoryFriendStore: FriendStoring {
    private var friends: [Friend]
    private var sessions: [UUID: StoredSession] = [:]
    private var imported: [UUID: TimetableResponse]

    init(friends: [Friend] = [], imported: [UUID: TimetableResponse] = [:]) {
        self.friends = friends
        self.imported = imported
    }

    func loadFriends() -> [Friend] { friends }
    func saveFriends(_ friends: [Friend]) throws { self.friends = friends }
    func loadSession(friendID: UUID) -> StoredSession? { sessions[friendID] }
    func saveSession(_ session: StoredSession, friendID: UUID) throws { sessions[friendID] = session }
    func loadImportedTimetable(friendID: UUID) -> TimetableResponse? { imported[friendID] }
    func saveImportedTimetable(_ response: TimetableResponse, friendID: UUID) throws { imported[friendID] = response }

    func removeData(friendID: UUID) {
        sessions[friendID] = nil
        imported[friendID] = nil
    }
}
