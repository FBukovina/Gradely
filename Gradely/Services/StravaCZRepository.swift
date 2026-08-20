import Foundation

struct StravaCZMenuData: Equatable {
    let session: StravaCZStoredSession
    let menu: StravaCZMenu
}

enum StravaCZAppError: LocalizedError, Equatable {
    case notLoggedIn
    case missingFields
    case mealNotFound
    case mealNotModifiable

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return AppL10n.string("error.stravacz.notLoggedIn")
        case .missingFields:
            return AppL10n.string("error.missingFields")
        case .mealNotFound:
            return AppL10n.string("error.stravacz.mealNotFound")
        case .mealNotModifiable:
            return AppL10n.string("error.stravacz.mealNotModifiable")
        }
    }
}

final class StravaCZRepository {
    private let client: any StravaCZClient
    private let sessionStore: any StravaCZSessionStoring
    private let menuCache: any StravaCZMenuCaching

    init(
        client: any StravaCZClient,
        sessionStore: any StravaCZSessionStoring,
        menuCache: any StravaCZMenuCaching
    ) {
        self.client = client
        self.sessionStore = sessionStore
        self.menuCache = menuCache
    }

    func bootstrapSession() throws -> StravaCZStoredSession? {
        try sessionStore.loadSession()
    }

    func loadCachedMenu() throws -> CachedStravaCZMenu? {
        try menuCache.load()
    }

    func login(canteenNumber: String, username: String, password: String) async throws -> StravaCZStoredSession {
        let trimmedCanteenNumber = canteenNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedCanteenNumber.isEmpty,
              !trimmedUsername.isEmpty,
              !password.isEmpty
        else {
            throw StravaCZAppError.missingFields
        }

        let response = try await client.login(
            username: trimmedUsername,
            password: password,
            canteenNumber: trimmedCanteenNumber
        )
        try? menuCache.clear()
        return try sessionStore.save(loginResponse: response)
    }

    func loadMenu(forceRefresh: Bool = false) async throws -> StravaCZMenuData {
        if forceRefresh {
            try? menuCache.clear()
        }

        let session = try validSession()

        do {
            let response = try await client.fetchMenu(session: session)
            let menu = StravaCZMenu.make(from: response)
            try menuCache.save(menu)
            return StravaCZMenuData(session: session, menu: menu)
        } catch {
            try clearIfAuthenticationError(error)
            throw error
        }
    }

    func setMeal(_ meal: StravaCZMeal, ordered: Bool) async throws -> StravaCZMenuData {
        guard meal.canModify else {
            throw StravaCZAppError.mealNotModifiable
        }

        var session = try validSession()

        do {
            let changeResponse = try await client.changeMealOrder(
                session: session,
                mealID: meal.id,
                ordered: ordered
            )
            if let balance = changeResponse.balance {
                session.balance = balance
                session.savedAt = Date()
                try sessionStore.save(session)
            }

            let saveResponse = try await client.saveOrders(session: session)
            if let balance = saveResponse.balance {
                session.balance = balance
                session.savedAt = Date()
                try sessionStore.save(session)
            }

            return try await loadMenu(forceRefresh: true)
        } catch {
            try? await rollbackPendingChanges()
            _ = try? await loadMenu(forceRefresh: true)
            try clearIfAuthenticationError(error)
            throw error
        }
    }

    func logout() async {
        let session = try? sessionStore.loadSession()
        try? sessionStore.clearSession()
        try? menuCache.clear()

        if let session {
            try? await client.logout(session: session)
        }
    }

    func clearLocalData() {
        try? sessionStore.clearSession()
        try? menuCache.clear()
    }

    func clearCachedMenu() {
        try? menuCache.clear()
    }

    private func validSession() throws -> StravaCZStoredSession {
        guard let session = try sessionStore.loadSession() else {
            throw StravaCZAppError.notLoggedIn
        }
        return session
    }

    private func rollbackPendingChanges() async throws {
        let session = try validSession()
        let response = try await client.cancelOrderChanges(session: session)
        if let balance = response.balance {
            var updatedSession = session
            updatedSession.balance = balance
            updatedSession.savedAt = Date()
            try sessionStore.save(updatedSession)
        }
    }

    private func clearIfAuthenticationError(_ error: Error) throws {
        if case StravaCZAPIError.authentication = error {
            try sessionStore.clearSession()
            try menuCache.clear()
        }
    }
}

final class MockStravaCZClient: StravaCZClient {
    var loginResult: StravaCZLoginResponse
    var menuResult: StravaCZMenuResponse
    var menuAfterOrderResult: StravaCZMenuResponse?
    var loginError: Error?
    var menuError: Error?
    var changeMealError: Error?
    var saveOrdersError: Error?
    var cancelChangesError: Error?
    private(set) var changeMealRequests: [(mealID: Int, ordered: Bool)] = []
    private(set) var didCancelOrderChanges = false
    private(set) var didLogout = false
    private var isOrdered = false

    init(
        loginResult: StravaCZLoginResponse = PreviewData.stravaCZLoginResponse,
        menuResult: StravaCZMenuResponse = PreviewData.stravaCZMenuResponse,
        menuAfterOrderResult: StravaCZMenuResponse? = PreviewData.stravaCZMenuAfterOrderResponse,
        loginError: Error? = nil,
        menuError: Error? = nil,
        changeMealError: Error? = nil,
        saveOrdersError: Error? = nil,
        cancelChangesError: Error? = nil
    ) {
        self.loginResult = loginResult
        self.menuResult = menuResult
        self.menuAfterOrderResult = menuAfterOrderResult
        self.loginError = loginError
        self.menuError = menuError
        self.changeMealError = changeMealError
        self.saveOrdersError = saveOrdersError
        self.cancelChangesError = cancelChangesError
    }

    func login(username: String, password: String, canteenNumber: String) async throws -> StravaCZLoginResponse {
        if let loginError { throw loginError }
        return loginResult
    }

    func fetchMenu(session: StravaCZStoredSession) async throws -> StravaCZMenuResponse {
        if let menuError { throw menuError }
        return isOrdered ? (menuAfterOrderResult ?? menuResult) : menuResult
    }

    func changeMealOrder(session: StravaCZStoredSession, mealID: Int, ordered: Bool) async throws -> StravaCZBalanceResponse {
        if let changeMealError { throw changeMealError }
        changeMealRequests.append((mealID, ordered))
        isOrdered = ordered
        return try JSONDecoder().decode(StravaCZBalanceResponse.self, from: Data(#"{"konto":"60.00"}"#.utf8))
    }

    func saveOrders(session: StravaCZStoredSession) async throws -> StravaCZBalanceResponse {
        if let saveOrdersError { throw saveOrdersError }
        return try JSONDecoder().decode(StravaCZBalanceResponse.self, from: Data(#"{"konto":"60.00"}"#.utf8))
    }

    func cancelOrderChanges(session: StravaCZStoredSession) async throws -> StravaCZBalanceResponse {
        if let cancelChangesError { throw cancelChangesError }
        didCancelOrderChanges = true
        return try JSONDecoder().decode(StravaCZBalanceResponse.self, from: Data(#"{"konto":"100.00"}"#.utf8))
    }

    func logout(session: StravaCZStoredSession) async throws {
        didLogout = true
    }
}
