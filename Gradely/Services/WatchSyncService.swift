import Foundation
import GradelyWatchShared
#if canImport(WatchConnectivity) && !os(macOS)
import WatchConnectivity
#endif

@MainActor
protocol WatchSyncing: AnyObject {
    func start()
    func update(session: StoredSession?)
    func update(user: UserResponse?)
    func update(timetable: GradelyWatchTimetable?)
    func publishSignedOut()
}

#if canImport(WatchConnectivity) && !os(macOS)
@MainActor
final class LiveWatchSyncService: NSObject, WatchSyncing {
    private var session: WCSession?
    private var activationState: WCSessionActivationState = .notActivated
    private var auth: GradelyWatchAuth?
    private var user: GradelyWatchUser?
    private var timetable: GradelyWatchTimetable?
    private var hasPendingPublish = false

    func start() {
        guard WCSession.isSupported() else { return }

        let wcSession = WCSession.default
        session = wcSession
        wcSession.delegate = self
        wcSession.activate()
    }

    func update(session: StoredSession?) {
        auth = session.map(WatchPayloadBuilder.auth)
        publishCurrentPayload()
    }

    func update(user: UserResponse?) {
        self.user = user.map(WatchPayloadBuilder.user)
        publishCurrentPayload()
    }

    func update(timetable: GradelyWatchTimetable?) {
        self.timetable = timetable
        publishCurrentPayload()
    }

    func publishSignedOut() {
        auth = nil
        user = nil
        timetable = nil
        publish(payload: .signedOut())
    }

    private var currentPayload: GradelyWatchSyncPayload {
        guard let auth else {
            return .signedOut()
        }

        return GradelyWatchSyncPayload(
            generatedAt: Date(),
            isSignedIn: true,
            auth: auth,
            user: user,
            timetable: timetable
        )
    }

    private func publishCurrentPayload() {
        publish(payload: currentPayload)
    }

    private func publish(payload: GradelyWatchSyncPayload) {
        guard let session else { return }
        guard activationState == .activated else {
            hasPendingPublish = true
            return
        }

        guard let envelope = try? GradelyWatchSyncCodec.envelope(for: payload) else {
            return
        }

        try? session.updateApplicationContext(envelope)
        session.transferUserInfo(envelope)

        if session.isReachable {
            session.sendMessage(envelope, replyHandler: nil, errorHandler: nil)
        }
    }

    private func handleActivation(state: WCSessionActivationState) {
        activationState = state
        guard state == .activated, hasPendingPublish else { return }

        hasPendingPublish = false
        publishCurrentPayload()
    }

    private func replyToSyncRequest(_ replyHandler: ([String: Any]) -> Void) {
        guard let envelope = try? GradelyWatchSyncCodec.envelope(for: currentPayload) else {
            replyHandler([:])
            return
        }

        replyHandler(envelope)
    }
}

extension LiveWatchSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.handleActivation(state: activationState)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard GradelyWatchSyncCodec.isRequestSync(message) else {
            replyHandler([:])
            return
        }

        Task { @MainActor in
            self.replyToSyncRequest(replyHandler)
        }
    }
}
#endif
