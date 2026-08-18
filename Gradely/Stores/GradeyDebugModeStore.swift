import Foundation

nonisolated final class GradeyDebugModeStore {
    static let storageKey = "gradey.debugMode.enabled.v1"
    static let launchArgument = "-gradeyDebugMode"
    static let requiredTapCount = 7

    private let userDefaults: UserDefaults

    init(
        userDefaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.userDefaults = userDefaults
        if processInfo.arguments.contains(Self.launchArgument) {
            isEnabled = true
        }
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: Self.storageKey) }
        set { userDefaults.set(newValue, forKey: Self.storageKey) }
    }

    /// Increments `tapCount` and enables debug mode after seven taps.
    /// Returns `true` when this tap unlocks the panel.
    func registerVersionTap(tapCount: inout Int) -> Bool {
        tapCount += 1
        guard tapCount >= Self.requiredTapCount else { return false }
        tapCount = 0
        isEnabled = true
        return true
    }
}
