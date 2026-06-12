import Foundation
import GradelyWatchShared
import WatchConnectivity

final class WatchConnectivityClient: NSObject {
    @MainActor var onPayload: ((GradelyWatchSyncPayload) -> Void)?
    private var session: WCSession?

    func start() {
        guard WCSession.isSupported() else { return }

        let wcSession = WCSession.default
        session = wcSession
        wcSession.delegate = self
        wcSession.activate()
    }

    func requestSync() {
        guard let session, session.activationState == .activated else { return }

        let request = GradelyWatchSyncCodec.requestSyncEnvelope()
        guard session.isReachable else { return }

        session.sendMessage(request) { [weak self] reply in
            self?.handle(envelope: reply)
        } errorHandler: { _ in }
    }

    private func handle(envelope: [String: Any]) {
        guard let payload = try? GradelyWatchSyncCodec.payload(from: envelope) else {
            return
        }

        Task { @MainActor in
            onPayload?(payload)
        }
    }
}

extension WatchConnectivityClient: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            requestSync()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(envelope: applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(envelope: userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(envelope: message)
    }
}
