import Foundation
import Observation

enum OnboardingJourney: String, Codable, Equatable, Sendable {
    case newUser
    case upgrade
}

enum OnboardingStep: String, Codable, Equatable, Sendable {
    case welcome
    case account
    case school
    case notifications
    case ready
    case support
}

struct OnboardingProgress: Codable, Equatable, Sendable {
    var journey: OnboardingJourney
    var step: OnboardingStep

    static func initial(for journey: OnboardingJourney) -> OnboardingProgress {
        OnboardingProgress(journey: journey, step: .welcome)
    }
}

enum OnboardingAccountIntent: Equatable, Sendable {
    case getStarted
    case logIn
}

enum OnboardingAccountMode: Equatable, Sendable {
    case undecided
    case guest
    case gradeyID
}

enum OnboardingNotificationStatus: Equatable, Sendable {
    case unavailable
    case notDetermined
    case enabled
    case notNow
    case denied
}

enum OnboardingMealsStatus: Equatable, Sendable {
    case notConnected
    case connected
}

enum OnboardingCloudLinkStatus: Equatable, Sendable {
    case notApplicable
    case notAttempted
    case linked
    case failed(message: String? = nil)
}

struct OnboardingWarning: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case schoolCloudLink
        case mealsCloudLink
        case notificationPreferences
    }

    let kind: Kind
    let message: String?

    var id: Kind { kind }
}

/// A non-sensitive view of persisted app state used to repair an interrupted flow.
struct OnboardingSnapshot: Equatable, Sendable {
    var accountMode: OnboardingAccountMode
    var hasSchoolConnection: Bool
    var isSchoolCloudLinked: Bool
    var notificationStatus: OnboardingNotificationStatus
    var hasMealsConnection: Bool
    var isMealsCloudLinked: Bool

    init(
        accountMode: OnboardingAccountMode = .undecided,
        hasSchoolConnection: Bool = false,
        isSchoolCloudLinked: Bool = false,
        notificationStatus: OnboardingNotificationStatus = .notDetermined,
        hasMealsConnection: Bool = false,
        isMealsCloudLinked: Bool = false
    ) {
        self.accountMode = accountMode
        self.hasSchoolConnection = hasSchoolConnection
        self.isSchoolCloudLinked = isSchoolCloudLinked
        self.notificationStatus = notificationStatus
        self.hasMealsConnection = hasMealsConnection
        self.isMealsCloudLinked = isMealsCloudLinked
    }
}

protocol OnboardingProgressStoring: AnyObject {
    func loadProgress() -> OnboardingProgress?
    func saveProgress(_ progress: OnboardingProgress)
    func clear()
}

final class OnboardingProgressStore: OnboardingProgressStoring {
    static let storageKey = "onboarding.progress.v2"
    static let completionKey = "onboarding.completed.v2"
    static let legacyCompletionKey = "onboarding.completed.v1"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadProgress() -> OnboardingProgress? {
        if let data = userDefaults.data(forKey: Self.storageKey),
           let progress = try? JSONDecoder().decode(OnboardingProgress.self, from: data) {
            return progress
        }

        // Repair progress written by the pre-release step-only implementation.
        guard let rawStep = userDefaults.string(forKey: Self.storageKey) else {
            return nil
        }
        let step: OnboardingStep
        if rawStep == "meals" {
            step = .ready
        } else if let decodedStep = OnboardingStep(rawValue: rawStep) {
            step = decodedStep == .support ? .account : decodedStep
        } else {
            userDefaults.removeObject(forKey: Self.storageKey)
            return nil
        }
        return OnboardingProgress(journey: .newUser, step: step)
    }

    func saveProgress(_ progress: OnboardingProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }
}

final class InMemoryOnboardingProgressStore: OnboardingProgressStoring {
    private(set) var savedProgress: OnboardingProgress?
    private(set) var saveCount = 0

    init(savedProgress: OnboardingProgress? = nil) {
        self.savedProgress = savedProgress
    }

    convenience init(journey: OnboardingJourney, step: OnboardingStep) {
        self.init(savedProgress: OnboardingProgress(journey: journey, step: step))
    }

    func loadProgress() -> OnboardingProgress? {
        savedProgress
    }

    func saveProgress(_ progress: OnboardingProgress) {
        saveCount += 1
        savedProgress = progress
    }

    func clear() {
        savedProgress = nil
    }
}

enum OnboardingRouteResolver {
    static func resolve(
        hasCompletedV2: Bool,
        hasCompletedV1: Bool,
        hasLegacySchoolSession: Bool,
        progressStore: any OnboardingProgressStoring
    ) -> OnboardingJourney? {
        if hasCompletedV2 {
            progressStore.clear()
            return nil
        }

        if let progress = progressStore.loadProgress() {
            return progress.journey
        }

        let journey: OnboardingJourney = hasCompletedV1 || hasLegacySchoolSession
            ? .upgrade
            : .newUser
        progressStore.saveProgress(.initial(for: journey))
        return journey
    }
}

@MainActor
@Observable
final class OnboardingViewModel {
    let journey: OnboardingJourney
    private(set) var currentStep: OnboardingStep
    private(set) var accountMode: OnboardingAccountMode = .undecided
    private(set) var hasSchoolConnection = false
    private(set) var hasMealsConnection = false
    private(set) var schoolCloudLinkStatus: OnboardingCloudLinkStatus = .notAttempted
    private(set) var notificationStatus: OnboardingNotificationStatus = .notDetermined
    private(set) var mealsStatus: OnboardingMealsStatus = .notConnected
    private(set) var mealsCloudLinkStatus: OnboardingCloudLinkStatus = .notAttempted
    private(set) var notificationSyncErrorMessage: String?
    private(set) var isFinished = false
    private(set) var hasRecordedUpgradeMigration = false
    private(set) var accountIntent: OnboardingAccountIntent = .getStarted

    private let progressStore: any OnboardingProgressStoring
    private var notificationReturnStep: OnboardingStep?

    init(
        journey: OnboardingJourney,
        progressStore: any OnboardingProgressStoring
    ) {
        self.journey = journey
        self.progressStore = progressStore

        if let savedProgress = progressStore.loadProgress(),
           savedProgress.journey == journey {
            currentStep = Self.validated(savedProgress.step, for: journey)
        } else {
            currentStep = OnboardingProgress.initial(for: journey).step
        }

        // Do not write UserDefaults from this initializer. SwiftUI may evaluate
        // a child view initializer repeatedly while updating its parent. A write
        // here invalidates ContentView's @AppStorage observation, which creates
        // another OnboardingView and can loop until the scene-create watchdog
        // terminates the app. The route resolver persists the initial journey;
        // subsequent user actions and reconciliation persist step changes.
    }

    var visibleSteps: [OnboardingStep] {
        switch journey {
        case .newUser:
            return [.account, .school, .notifications, .ready].filter {
                $0 != .notifications || notificationStatus != .unavailable
            }
        case .upgrade:
            return [.account, .support]
        }
    }

    var progressPosition: Int {
        (visibleSteps.firstIndex(of: currentStep) ?? 0) + 1
    }

    var progressCount: Int {
        visibleSteps.count
    }

    var progressFraction: Double {
        Double(progressPosition) / Double(max(progressCount, 1))
    }

    var canGoBack: Bool {
        currentStep != .welcome && currentStep != .support
    }

    var canFinish: Bool {
        switch journey {
        case .newUser:
            currentStep == .ready
                && accountMode == .gradeyID
                && hasSchoolConnection
        case .upgrade:
            currentStep == .support
                && (accountMode != .gradeyID || hasRecordedUpgradeMigration)
        }
    }

    var warnings: [OnboardingWarning] {
        var result: [OnboardingWarning] = []
        if case .failed(let message) = schoolCloudLinkStatus {
            result.append(OnboardingWarning(kind: .schoolCloudLink, message: message))
        }
        if journey == .upgrade, case .failed(let message) = mealsCloudLinkStatus {
            result.append(OnboardingWarning(kind: .mealsCloudLink, message: message))
        }
        if let notificationSyncErrorMessage {
            result.append(OnboardingWarning(
                kind: .notificationPreferences,
                message: notificationSyncErrorMessage
            ))
        }
        return result
    }

    /// Rebuilds transient status from Keychain/auth/repository state without marking onboarding complete.
    func reconcile(with snapshot: OnboardingSnapshot) {
        guard !isFinished else { return }

        accountMode = snapshot.accountMode
        hasSchoolConnection = snapshot.hasSchoolConnection
        hasMealsConnection = snapshot.hasMealsConnection
        mealsStatus = snapshot.hasMealsConnection ? .connected : .notConnected

        schoolCloudLinkStatus = reconciledCloudLinkStatus(
            existing: schoolCloudLinkStatus,
            isLocallyConnected: snapshot.hasSchoolConnection,
            isCloudLinked: snapshot.isSchoolCloudLinked
        )
        mealsCloudLinkStatus = reconciledCloudLinkStatus(
            existing: mealsCloudLinkStatus,
            isLocallyConnected: snapshot.hasMealsConnection,
            isCloudLinked: snapshot.isMealsCloudLinked
        )
        notificationStatus = reconciledNotificationStatus(
            snapshot.notificationStatus,
            accountMode: snapshot.accountMode,
            isSchoolCloudLinked: snapshot.isSchoolCloudLinked
        )

        currentStep = reconciledStep(currentStep)
        saveProgress()
    }

    func advanceFromWelcome() {
        chooseGetStarted()
    }

    func chooseGetStarted() {
        accountIntent = .getStarted
        setStep(.account)
    }

    func chooseLogIn() {
        accountIntent = .logIn
        setStep(.account)
    }

    func skipWelcome() {
        chooseGetStarted()
    }

    func chooseGuest() {
        guard journey == .upgrade else { return }
        accountMode = .guest
        notificationStatus = .unavailable
        schoolCloudLinkStatus = .notApplicable
        mealsCloudLinkStatus = .notApplicable
        setStep(.support)
    }

    func markSignedIn() {
        accountMode = .gradeyID
        if notificationStatus == .unavailable {
            notificationStatus = .notDetermined
        }

        switch journey {
        case .newUser:
            setStep(hasSchoolConnection ? nextStepAfterSchool : .school)
        case .upgrade:
            setStep(.support)
        }
    }

    /// Records the durable local connection first, so a cloud-link failure remains non-blocking.
    func markSchoolConnected(cloudLink: OnboardingCloudLinkStatus = .notAttempted) {
        guard journey == .newUser else { return }
        hasSchoolConnection = true
        schoolCloudLinkStatus = normalizedCloudLinkStatus(cloudLink)
        if schoolCloudLinkStatus != .linked {
            notificationStatus = .unavailable
        }
        setStep(nextStepAfterSchool)
    }

    func markNotification(_ status: OnboardingNotificationStatus) {
        guard journey == .newUser, accountMode == .gradeyID else {
            notificationStatus = .unavailable
            setStep(.ready)
            return
        }
        guard status == .enabled || status == .denied || status == .notNow else {
            notificationStatus = status
            return
        }

        notificationStatus = status
        if let notificationReturnStep {
            self.notificationReturnStep = nil
            setStep(notificationReturnStep)
        } else {
            setStep(.ready)
        }
    }

    func skipNotifications() {
        markNotification(.notNow)
    }

    func recordUpgradeMigration(
        school: OnboardingCloudLinkStatus,
        meals: OnboardingCloudLinkStatus
    ) {
        guard journey == .upgrade else { return }
        schoolCloudLinkStatus = normalizedCloudLinkStatus(school)
        mealsCloudLinkStatus = normalizedCloudLinkStatus(meals)
        hasRecordedUpgradeMigration = true
    }

    func recordSchoolCloudLinkRetry(_ status: OnboardingCloudLinkStatus) {
        guard hasSchoolConnection else { return }
        schoolCloudLinkStatus = normalizedCloudLinkStatus(status)
    }

    /// Reopens notification opt-in after a failed school cloud link succeeds.
    @discardableResult
    func openNotificationsAfterSchoolLinkRetry() -> Bool {
        guard journey == .newUser,
              accountMode == .gradeyID,
              hasSchoolConnection,
              schoolCloudLinkStatus == .linked,
              notificationStatus == .unavailable
        else {
            return false
        }

        notificationReturnStep = currentStep == .ready ? .ready : nil
        notificationStatus = .notDetermined
        setStep(.notifications)
        return true
    }

    func recordMealsCloudLinkRetry(_ status: OnboardingCloudLinkStatus) {
        guard hasMealsConnection else { return }
        mealsCloudLinkStatus = normalizedCloudLinkStatus(status)
    }

    func recordNotificationSyncFailure(_ message: String) {
        notificationSyncErrorMessage = message
    }

    func clearNotificationSyncFailure() {
        notificationSyncErrorMessage = nil
    }

    func goBack() {
        let destination: OnboardingStep?
        switch currentStep {
        case .welcome:
            destination = nil
        case .account:
            destination = .welcome
        case .school:
            destination = .account
        case .notifications:
            destination = notificationReturnStep ?? .school
            notificationReturnStep = nil
        case .ready:
            destination = notificationStatus == .unavailable ? .school : .notifications
        case .support:
            destination = .account
        }

        guard let destination else { return }
        setStep(destination)
    }

    /// The caller owns `onboarding.completed.v2` and should set it only when this returns true.
    @discardableResult
    func finish() -> Bool {
        guard canFinish else { return false }
        progressStore.clear()
        isFinished = true
        return true
    }

    private var nextStepAfterSchool: OnboardingStep {
        accountMode == .gradeyID && schoolCloudLinkStatus == .linked
            ? .notifications
            : .ready
    }

    private func reconciledStep(_ savedStep: OnboardingStep) -> OnboardingStep {
        switch journey {
        case .newUser:
            guard savedStep != .welcome else { return .welcome }
            guard accountMode == .gradeyID else { return .account }
            guard hasSchoolConnection else { return .school }

            if savedStep == .ready {
                return .ready
            }
            if savedStep == .notifications,
               schoolCloudLinkStatus == .linked,
               notificationStatus == .notDetermined {
                return .notifications
            }
            return nextStepAfterSchool

        case .upgrade:
            if accountMode == .gradeyID || savedStep == .support {
                return .support
            }
            if savedStep == .welcome {
                return .welcome
            }
            return .account
        }
    }

    private func reconciledNotificationStatus(
        _ status: OnboardingNotificationStatus,
        accountMode: OnboardingAccountMode,
        isSchoolCloudLinked: Bool
    ) -> OnboardingNotificationStatus {
        guard accountMode == .gradeyID, isSchoolCloudLinked else {
            return .unavailable
        }
        if currentStep == .ready, status == .notDetermined {
            return .notNow
        }
        return status
    }

    private func reconciledCloudLinkStatus(
        existing: OnboardingCloudLinkStatus,
        isLocallyConnected: Bool,
        isCloudLinked: Bool
    ) -> OnboardingCloudLinkStatus {
        guard isLocallyConnected else { return .notAttempted }
        guard accountMode == .gradeyID else { return .notApplicable }
        if isCloudLinked {
            return .linked
        }
        if case .failed = existing {
            return existing
        }
        if currentStep == .ready || currentStep == .support {
            return .failed()
        }
        return .notAttempted
    }

    private func normalizedCloudLinkStatus(
        _ status: OnboardingCloudLinkStatus
    ) -> OnboardingCloudLinkStatus {
        accountMode == .gradeyID ? status : .notApplicable
    }

    private func setStep(_ step: OnboardingStep) {
        currentStep = Self.validated(step, for: journey)
        saveProgress()
    }

    private func saveProgress() {
        progressStore.saveProgress(OnboardingProgress(journey: journey, step: currentStep))
    }

    private static func validated(
        _ step: OnboardingStep,
        for journey: OnboardingJourney
    ) -> OnboardingStep {
        switch journey {
        case .newUser:
            return step == .support ? .welcome : step
        case .upgrade:
            switch step {
            case .welcome, .account, .support:
                return step
            default:
                return .welcome
            }
        }
    }
}
