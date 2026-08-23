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
    func restart(_ journey: OnboardingJourney, at step: OnboardingStep? = nil) -> OnboardingJourney {
        userDefaults.removeObject(forKey: OnboardingProgressStore.completionKey)
        progressStore.clear()

        switch journey {
        case .newUser:
            userDefaults.removeObject(forKey: OnboardingProgressStore.legacyCompletionKey)
        case .upgrade:
            userDefaults.set(true, forKey: OnboardingProgressStore.legacyCompletionKey)
        }

        var progress = OnboardingProgress.initial(for: journey)
        if let step {
            progress.step = step
        }
        progressStore.saveProgress(progress)
        return journey
    }
}
