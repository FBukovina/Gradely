import Foundation
import Observation

enum AgeAttestationKind: String, Codable, Equatable, Sendable {
    case sixteenOrOlder
    case thirteenToFifteenWithParent
    case underThirteen

    var allowsAppUse: Bool {
        switch self {
        case .sixteenOrOlder, .thirteenToFifteenWithParent:
            true
        case .underThirteen:
            false
        }
    }
}

/// COPPA (under 13) and GDPR Art. 8 (Czech digital consent age is 15).
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

    func clearBlockedChoice() {
        guard kind == .underThirteen else { return }
        kind = nil
    }

    private func persist() {
        if let kind {
            userDefaults.set(kind.rawValue, forKey: Self.storageKey)
        } else {
            userDefaults.removeObject(forKey: Self.storageKey)
        }
    }
}
