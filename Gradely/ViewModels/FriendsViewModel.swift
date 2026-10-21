import Foundation
import Observation

/// One app-wide list of friends, shared by the Timetable switcher and Settings.
@MainActor
@Observable
final class FriendsViewModel {
    private(set) var friends: [Friend] = []

    @ObservationIgnored let repository: FriendRepository
    @ObservationIgnored let schoolDirectoryProvider: any SchoolDirectoryProviding
    /// Your own Bakaláři school, to suggest it first: friends are often classmates.
    @ObservationIgnored let ownSchoolURL: () -> URL?

    init(
        repository: FriendRepository,
        schoolDirectoryProvider: any SchoolDirectoryProviding,
        ownSchoolURL: @escaping () -> URL? = { nil }
    ) {
        self.repository = repository
        self.schoolDirectoryProvider = schoolDirectoryProvider
        self.ownSchoolURL = ownSchoolURL
        friends = repository.loadFriends()
    }

    func friend(id: UUID?) -> Friend? {
        friends.first { $0.id == id }
    }

    func add(_ friend: Friend) {
        friends.append(friend)
        repository.save(friends)
    }

    func rename(_ friend: Friend, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = friends.firstIndex(where: { $0.id == friend.id }) else { return }
        friends[index].name = name
        repository.save(friends)
    }

    func remove(_ friend: Friend) {
        friends.removeAll { $0.id == friend.id }
        repository.save(friends)
        repository.removeData(for: friend)
    }

    /// Signing out takes friends' logins off the device too.
    func removeAll() {
        friends.forEach(repository.removeData(for:))
        friends = []
        repository.save([])
    }

    func clearCaches() {
        repository.clearCache(for: friends)
    }

    func timetableSource(for friend: Friend) -> TimetableSource {
        let repository = repository
        return TimetableSource(
            supportsPermanentTimetable: { friend.source.supportsPermanentTimetable },
            schoolScope: { nil },
            cachedWeek: { date, kind in repository.cachedWeek(for: friend, weekContaining: date, kind: kind) },
            loadWeek: { date, kind in try await repository.loadWeek(for: friend, weekContaining: date, kind: kind) },
            loadUser: { nil }
        )
    }
}
