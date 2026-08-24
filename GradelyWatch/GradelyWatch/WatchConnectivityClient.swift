import Foundation
import GradelyWatchShared
import WatchConnectivity

enum WatchAITransportError: LocalizedError {
    case notActivated
    case phoneUnreachable
    case invalidReply

    var errorDescription: String? {
        switch self {
        case .notActivated, .phoneUnreachable:
            return "Bring iPhone nearby to use Gradey AI."
        case .invalidReply:
            return "The iPhone did not accept the Gradey AI request."
        }
    }
}

enum WatchPurchaseRefreshError: LocalizedError {
    case notActivated
    case phoneUnreachable
    case invalidReply

    var errorDescription: String? {
        switch self {
        case .notActivated, .phoneUnreachable:
            return "Bring iPhone nearby to refresh purchases."
        case .invalidReply:
            return "Could not refresh purchases. Open Gradey on iPhone and try again."
        }
    }
}

final class WatchConnectivityClient: NSObject {
    @MainActor var onPayload: ((GradelyWatchSyncPayload) -> Void)?
    @MainActor var onAIEvent: ((GradelyWatchAIStreamEvent) -> Void)?
    @MainActor var onReachabilityChange: ((Bool) -> Void)?

    private var session: WCSession?

    var isReachable: Bool {
        session?.isReachable ?? false
    }

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

    func requestPurchaseRefresh() async throws -> GradelyWatchSyncPayload {
        guard let session, session.activationState == .activated else {
            throw WatchPurchaseRefreshError.notActivated
        }
        guard session.isReachable else {
            throw WatchPurchaseRefreshError.phoneUnreachable
        }

        let envelope = GradelyWatchSyncCodec.requestPurchaseRefreshEnvelope()
        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            func resume(_ result: Result<GradelyWatchSyncPayload, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            session.sendMessage(envelope, replyHandler: { reply in
                do {
                    guard let payload = try GradelyWatchSyncCodec.payload(from: reply) else {
                        resume(.failure(WatchPurchaseRefreshError.invalidReply))
                        return
                    }
                    resume(.success(payload))
                } catch {
                    resume(.failure(error))
                }
            }, errorHandler: { error in
                resume(.failure(error))
            })
        }
    }

    func sendAIRequest(_ request: GradelyWatchAIStreamRequest) async throws -> GradelyWatchAIStreamAck {
        guard let session, session.activationState == .activated else {
            throw WatchAITransportError.notActivated
        }
        guard session.isReachable else {
            throw WatchAITransportError.phoneUnreachable
        }

        let envelope = try GradelyWatchSyncCodec.envelope(for: request)
        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            func resume(_ result: Result<GradelyWatchAIStreamAck, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            session.sendMessage(envelope, replyHandler: { reply in
                do {
                    guard let ack = try GradelyWatchSyncCodec.aiAck(from: reply) else {
                        resume(.failure(WatchAITransportError.invalidReply))
                        return
                    }
                    resume(.success(ack))
                } catch {
                    resume(.failure(error))
                }
            }, errorHandler: { error in
                resume(.failure(error))
            })
        }
    }

    func sendAICancel(_ cancel: GradelyWatchAICancel) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        guard let envelope = try? GradelyWatchSyncCodec.envelope(for: cancel) else { return }
        session.sendMessage(envelope, replyHandler: nil, errorHandler: nil)
    }

    private func handle(envelope: [String: Any]) {
        if let event = try? GradelyWatchSyncCodec.aiEvent(from: envelope) {
            Task { @MainActor in
                onAIEvent?(event)
            }
            return
        }

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
        Task { @MainActor in
            onReachabilityChange?(session.isReachable)
        }
        if activationState == .activated {
            requestSync()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            onReachabilityChange?(session.isReachable)
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
