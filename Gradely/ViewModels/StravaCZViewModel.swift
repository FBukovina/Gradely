import Foundation
import Observation

@MainActor
@Observable
final class StravaCZViewModel {
    enum Phase: Equatable {
        case checking
        case signedOut
        case signedIn
    }

    var phase: Phase = .checking
    var canteenNumber = ""
    var username = ""
    var isLoading = false
    var isRefreshing = false
    var submittingMealID: Int?
    var session: StravaCZStoredSession?
    var menu: StravaCZMenu?
    var lastCacheDate: Date?
    var errorMessage: String?
    var pendingReplacement: StravaCZReplacementConfirmation?

    private let repository: StravaCZRepository
    private let linkedAccountRepository: LinkedAccountRepository?
    private var hasBootstrapped = false

    init(repository: StravaCZRepository, linkedAccountRepository: LinkedAccountRepository? = nil) {
        self.repository = repository
        self.linkedAccountRepository = linkedAccountRepository
    }

    var isBusy: Bool {
        isLoading || isRefreshing || submittingMealID != nil
    }

    func bootstrap() async {
        guard !hasBootstrapped else {
            resyncWithStoredSession()
            return
        }
        hasBootstrapped = true

        do {
            guard let storedSession = try repository.bootstrapSession() else {
                phase = .signedOut
                return
            }

            session = storedSession
            canteenNumber = storedSession.canteenNumber
            username = storedSession.username
            phase = .signedIn

            if let cached = try? repository.loadCachedMenu() {
                menu = cached.menu
                lastCacheDate = cached.cachedAt
            }

            await refresh(forceRefresh: false)
        } catch {
            phase = .signedOut
        }
    }

    func didConnect(_ session: StravaCZStoredSession) async {
        self.session = session
        canteenNumber = session.canteenNumber
        username = session.username
        phase = .signedIn

        // Best effort: without a Gradey session (gate off) the meals
        // connection must still work locally.
        if let linkedAccountRepository {
            _ = try? await linkedAccountRepository.linkCurrentStravaCZAccount(session: session)
        }

        await refresh(forceRefresh: true)
    }

    /// The account hub can connect or unlink Strava.cz behind this tab's back;
    /// `.task` re-fires when the tab reappears, so realign phase with the
    /// keychain session instead of trusting the first bootstrap forever.
    private func resyncWithStoredSession() {
        let storedSession = try? repository.bootstrapSession()

        switch (phase, storedSession) {
        case (.signedOut, .some(let stored)):
            session = stored
            canteenNumber = stored.canteenNumber
            username = stored.username
            phase = .signedIn
            if let cached = try? repository.loadCachedMenu() {
                menu = cached.menu
                lastCacheDate = cached.cachedAt
            }
        case (.signedIn, .none):
            resetSignedOutState()
        default:
            break
        }
    }

    func refresh(forceRefresh: Bool = true) async {
        guard phase == .signedIn else { return }

        errorMessage = nil
        if menu == nil {
            isLoading = true
        } else {
            isRefreshing = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let data = try await repository.loadMenu(forceRefresh: forceRefresh)
            session = data.session
            menu = data.menu
            lastCacheDate = Date()
        } catch {
            handle(error)
        }
    }

    func toggleMeal(_ meal: StravaCZMeal) async {
        guard meal.canModify else { return }

        if meal.ordered {
            await setMeal(meal, ordered: false)
            return
        }

        if let existing = day(containing: meal)?.orderedMainMeal, existing.id != meal.id {
            pendingReplacement = StravaCZReplacementConfirmation(existingMeal: existing, newMeal: meal)
            return
        }

        await setMeal(meal, ordered: true)
    }

    func confirmReplacement() async {
        guard let replacement = pendingReplacement else { return }
        pendingReplacement = nil
        await setMeal(replacement.newMeal, ordered: true)
    }

    func disconnect() async {
        if let linkedAccountRepository {
            for account in linkedAccountRepository.loadAccounts() where account.provider == .stravaCZ {
                try? await linkedAccountRepository.unlinkAccount(id: account.id)
            }
        }
        await repository.logout()
        resetSignedOutState()
    }

    func clearError() {
        errorMessage = nil
    }

    private func setMeal(_ meal: StravaCZMeal, ordered: Bool) async {
        errorMessage = nil
        submittingMealID = meal.id
        defer { submittingMealID = nil }

        do {
            let data = try await repository.setMeal(meal, ordered: ordered)
            session = data.session
            menu = data.menu
            lastCacheDate = Date()
        } catch {
            handle(error)
        }
    }

    private func day(containing meal: StravaCZMeal) -> StravaCZMenuDay? {
        menu?.days.first { $0.dateKey == meal.dateKey }
    }

    private func handle(_ error: Error) {
        if case StravaCZAppError.notLoggedIn = error {
            resetSignedOutState()
            errorMessage = userFacingMessage(for: error)
            return
        }
        if case StravaCZAPIError.authentication = error {
            resetSignedOutState()
            errorMessage = userFacingMessage(for: error)
            return
        }

        errorMessage = userFacingMessage(for: error)
    }

    private func resetSignedOutState() {
        phase = .signedOut
        session = nil
        menu = nil
        lastCacheDate = nil
        pendingReplacement = nil
        submittingMealID = nil
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}

struct StravaCZReplacementConfirmation: Equatable, Identifiable {
    let id = UUID()
    let existingMeal: StravaCZMeal
    let newMeal: StravaCZMeal
}
