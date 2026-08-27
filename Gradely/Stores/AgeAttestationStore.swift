import Foundation
import Observation

enum AgeAttestationKind: String, Codable, Equatable, Sendable {
    case sixteenOrOlder
    case thirteenToFifteenWithParent
    case underThirteen

    /// EU storefronts only: GDPR Art. 8 parental consent, no COPPA hard stop.
    var allowsAppUse: Bool {
        true
    }

    var needsParentalConsent: Bool {
        switch self {
        case .sixteenOrOlder:
            false
        case .thirteenToFifteenWithParent, .underThirteen:
            true
        }
    }
}

/// GDPR Art. 8 for European storefronts. Uses the GDPR default digital-consent
/// age of 16. Under-16 use, including under 13, needs a parent or guardian.
/// Stores a self-attestation only — no birth date.
@Observable
final class AgeAttestationStore {
    static let shared = AgeAttestationStore()
    static let storageKey = "gradey.ageAttestation.v1"
    static let uiTestingShowArgument = "-uiTestingShowAgeGate"

    private let userDefaults: UserDefaults

    var kind: AgeAttestationKind? {
        didSet { persist() }
    }

    var allowsAppUse: Bool {
        kind?.allowsAppUse == true
    }

    nonisolated static func allowsAppUse(userDefaults: UserDefaults = .standard) -> Bool {
        AgeAttestationKind(rawValue: userDefaults.string(forKey: storageKey) ?? "")?.allowsAppUse == true
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: Self.storageKey) {
            kind = AgeAttestationKind(rawValue: raw)
        }
    }

    func confirm(_ kind: AgeAttestationKind) {
        self.kind = kind
    }

    private func persist() {
        if let kind {
            userDefaults.set(kind.rawValue, forKey: Self.storageKey)
        } else {
            userDefaults.removeObject(forKey: Self.storageKey)
        }
    }
}
