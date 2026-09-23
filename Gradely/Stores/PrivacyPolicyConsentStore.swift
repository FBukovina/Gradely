import Foundation
import Observation

/// Records which privacy-policy revision the person on this device has read and
/// accepted. Device-local by design: the acceptance is not sent to the backend,
/// so acknowledging the policy does not itself create a new record about you.
///
/// Mirrors `AgeAttestationStore`: an observable singleton over `UserDefaults`
/// with an injectable store for tests and a launch argument for UI tests.
@Observable
final class PrivacyPolicyConsentStore {
    static let shared = PrivacyPolicyConsentStore()
    static let versionKey = "gradey.privacyPolicy.acceptedVersion.v1"
    static let dateKey = "gradey.privacyPolicy.acceptedAt.v1"
    /// Clears the stored acceptance so the sheet appears on the next launch.
    static let uiTestingShowArgument = "-uiTestingShowPrivacyUpdate"

    private let userDefaults: UserDefaults

    private(set) var acceptedVersion: Int?
    private(set) var acceptedAt: Date?

    /// `true` while the current revision has not been accepted on this device.
    var needsAcknowledgement: Bool {
        (acceptedVersion ?? 0) < PrivacyPolicyRevision.current
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        // `object(forKey:)` rather than `integer(forKey:)` so a device that has
        // never stored the key stays distinguishable from one that stored 0.
        acceptedVersion = userDefaults.object(forKey: Self.versionKey) as? Int
        acceptedAt = (userDefaults.string(forKey: Self.dateKey)).flatMap(Self.formatter.date(from:))
    }

    /// Records acceptance of the revision the app currently ships. Idempotent.
    func accept(at date: Date = Date()) {
        acceptedVersion = PrivacyPolicyRevision.current
        acceptedAt = date
        userDefaults.set(PrivacyPolicyRevision.current, forKey: Self.versionKey)
        userDefaults.set(Self.formatter.string(from: date), forKey: Self.dateKey)
    }

    func clear() {
        acceptedVersion = nil
        acceptedAt = nil
        userDefaults.removeObject(forKey: Self.versionKey)
        userDefaults.removeObject(forKey: Self.dateKey)
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// How much of the policy summary has been read.
///
/// Split out from the view so the gate's arithmetic and its latch are testable
/// without a running `ScrollView`.
struct PrivacyPolicyReadProgress: Equatable, Sendable {
    /// Treat anything past this as the bottom; `ScrollView` rarely reports an
    /// exact 1.0 because of rubber-banding and fractional insets.
    static let completionThreshold: Double = 0.98

    private(set) var fraction: Double = 0
    /// Latched: once the bottom has been reached, scrolling back up must not
    /// re-lock the button.
    private(set) var hasReachedEnd = false

    /// Fraction of the scrollable distance currently above the viewport.
    /// Content that fits without scrolling counts as fully read.
    static func fraction(
        contentHeight: Double,
        containerHeight: Double,
        offset: Double
    ) -> Double {
        let scrollable = contentHeight - containerHeight
        guard scrollable > 1 else { return 1 }
        return min(max(offset / scrollable, 0), 1)
    }

    mutating func update(fraction newFraction: Double) {
        fraction = min(max(newFraction, 0), 1)
        if fraction >= Self.completionThreshold {
            hasReachedEnd = true
        }
    }

    /// Unlocks immediately for VoiceOver, where a scroll-position gate is not
    /// reachable and would otherwise lock the person out of the app.
    func isSatisfied(voiceOverEnabled: Bool) -> Bool {
        hasReachedEnd || voiceOverEnabled
    }
}
