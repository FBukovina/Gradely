import Foundation
import GradelyWatchShared
import Testing
@testable import Gradely

@MainActor
struct WatchSyncTests {
    @Test func repositoryPublishesSessionAfterLogin() async throws {
        let watchSync = RecordingWatchSyncService()
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(),
            marksCache: InMemoryMarksCache(),
            watchSyncService: watchSync
        )

        let session = try await repository.login(
            schoolURL: "https://demo.gradely.app",
            username: "student",
            password: "password"
        )

        #expect(watchSync.sessions == [session])
    }

    @Test func repositoryPublishesTimetableAfterLoad() async throws {
        let watchSync = RecordingWatchSyncService()
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(),
            timetableCache: InMemoryTimetableCache(),
            watchSyncService: watchSync
        )

        _ = try await repository.loadTimetable(weekContaining: Date())

        #expect(watchSync.timetables.count == 1)
        #expect(watchSync.timetables[0]?.days.isEmpty == false)
    }

    @Test func repositoryPublishesSignedOutOnLogout() throws {
        let watchSync = RecordingWatchSyncService()
        let repository = SchoolRepository(
            client: MockBakalariClient(),
            sessionStore: InMemorySessionStore(session: PreviewData.expiredSession),
            marksCache: InMemoryMarksCache(),
            timetableCache: InMemoryTimetableCache(),
            watchSyncService: watchSync
        )

        try repository.logout()

        #expect(watchSync.didPublishSignedOut)
    }
}

@MainActor
private final class RecordingWatchSyncService: WatchSyncing {
    private(set) var sessions: [StoredSession?] = []
    private(set) var users: [UserResponse?] = []
    private(set) var timetables: [GradelyWatchTimetable?] = []
    private(set) var didPublishSignedOut = false

    func start() {}

    func update(session: StoredSession?) {
        sessions.append(session)
    }

    func update(user: UserResponse?) {
        users.append(user)
    }

    func update(timetable: GradelyWatchTimetable?) {
        timetables.append(timetable)
    }

    func publishSignedOut() {
        didPublishSignedOut = true
    }
}
