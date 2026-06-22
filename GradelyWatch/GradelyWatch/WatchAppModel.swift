import Combine
import Foundation
import GradelyWatchShared
import WidgetKit

@MainActor
final class WatchAppModel: ObservableObject {
    @Published private(set) var auth: GradelyWatchAuth?
    @Published private(set) var user: GradelyWatchUser?
    @Published private(set) var timetable: GradelyWatchTimetable?
    @Published private(set) var isSyncing = false
    @Published private(set) var errorMessage: String?

    private let connectivity: WatchConnectivityClient
    private let sessionStore: WatchSessionStore
    private let timetableCache: WatchTimetableCache
    private let client: WatchBakalariClient
    private var hasStarted = false

    init(
        connectivity: WatchConnectivityClient = WatchConnectivityClient(),
        sessionStore: WatchSessionStore = WatchSessionStore(),
        timetableCache: WatchTimetableCache = WatchTimetableCache(),
        client: WatchBakalariClient = WatchBakalariClient()
    ) {
        self.connectivity = connectivity
        self.sessionStore = sessionStore
        self.timetableCache = timetableCache
        self.client = client
    }

    var isSignedIn: Bool {
        auth != nil
    }

    var statusTitle: String {
        if !isSignedIn {
            return "Not signed in"
        }
        if let errorMessage, !errorMessage.isEmpty {
            return "Needs attention"
        }
        switch lessonSelection {
        case .lesson:
            return "Timetable"
        case .noTimetable:
            return "Syncing timetable"
        case .noLessons:
            return "Done for today"
        case .stale:
            return "Timetable is stale"
        }
    }

    var lessonSelection: GradelyWatchLessonSelection {
        GradelyWatchSyncCodec.selectLesson(from: timetable)
    }

    var nowAndNext: GradelyWatchNowNext {
        GradelyWatchSyncCodec.nowAndNext(from: timetable)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        connectivity.onPayload = { [weak self] payload in
            Task { @MainActor in
                await self?.apply(payload)
            }
        }
        connectivity.start()

        auth = try? sessionStore.load()
        timetable = try? timetableCache.load()
        connectivity.requestSync()

        if auth != nil {
            await refreshTimetable()
        }
    }

    func refreshTimetable() async {
        guard var currentAuth = auth ?? (try? sessionStore.load()) else {
            auth = nil
            return
        }

        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            if currentAuth.expiresSoon() {
                currentAuth = try await client.refresh(auth: currentAuth)
                auth = currentAuth
                try sessionStore.save(currentAuth)
            }

            let loaded: GradelyWatchTimetable
            do {
                loaded = try await client.fetchTimetable(auth: currentAuth, weekContaining: Date())
            } catch {
                // Session rejected mid-fetch: re-establish once and retry. EduPage
                // cookies can expire silently; for Bakaláři a 401 means the shared
                // access token was invalidated, so re-login onto our own token family.
                guard currentAuth.resolvedProvider == .eduPage || isAuthFailure(error) else { throw error }
                currentAuth = try await client.refresh(auth: currentAuth)
                auth = currentAuth
                try sessionStore.save(currentAuth)
                loaded = try await client.fetchTimetable(auth: currentAuth, weekContaining: Date())
            }
            timetable = loaded
            try timetableCache.save(loaded)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func apply(_ payload: GradelyWatchSyncPayload) async {
        guard payload.isSignedIn, let payloadAuth = payload.auth else {
            auth = nil
            user = nil
            timetable = nil
            errorMessage = nil
            try? sessionStore.clear()
            try? timetableCache.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        auth = payloadAuth
        user = payload.user
        try? sessionStore.save(payloadAuth)

        if let payloadTimetable = payload.timetable {
            timetable = payloadTimetable
            try? timetableCache.save(payloadTimetable)
            WidgetCenter.shared.reloadAllTimelines()
        }

        await refreshTimetable()
    }

    private func isAuthFailure(_ error: Error) -> Bool {
        if case WatchBakalariError.httpStatus(401, _) = error {
            return true
        }
        return false
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
