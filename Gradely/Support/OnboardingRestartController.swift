import Foundation

struct OnboardingRestartController {
    let userDefaults: UserDefaults
    let progressStore: any OnboardingProgressStoring

    init(
        userDefaults: UserDefaults = .standard,
        progressStore: any OnboardingProgressStoring
    ) {
        self.userDefaults = userDefaults
        self.progressStore = progressStore
    }

    /// Forces the given journey regardless of leftover school sessions or v1 flags.
    @discardableResult
    func restart(_ journey: OnboardingJourney) -> OnboardingJourney {
        userDefaults.removeObject(forKey: OnboardingProgressStore.completionKey)
        progressStore.clear()

        switch journey {
        case .newUser:
            userDefaults.removeObject(forKey: OnboardingProgressStore.legacyCompletionKey)
        case .upgrade:
            userDefaults.set(true, forKey: OnboardingProgressStore.legacyCompletionKey)
        }

        progressStore.saveProgress(.initial(for: journey))
        return journey
    }
}
