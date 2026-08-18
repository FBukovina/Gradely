import Foundation

nonisolated protocol GradeyGuestModeStoring: AnyObject {
    var isEnabled: Bool { get set }
}

nonisolated final class GradeyGuestModeStore: GradeyGuestModeStoring {
    static let storageKey = "gradey.guestMode.enabled.v1"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: Self.storageKey) }
        set { userDefaults.set(newValue, forKey: Self.storageKey) }
    }
}

nonisolated final class InMemoryGradeyGuestModeStore: GradeyGuestModeStoring {
    var isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}
