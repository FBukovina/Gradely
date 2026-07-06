import Foundation
import Testing
@testable import Gradely

@MainActor
struct StravaCZTests {
    @Test func parsesMenuDatesAndSkipsPlaceholderMeals() throws {
        let json = """
        {
          "table0": [
            {
              "id": 0,
              "datum": "15.09.2025",
              "druh_popis": "Oběd 1",
              "delsiPopis": "",
              "nazev": "Oběd 1",
              "zakazaneAlergeny": null,
              "alergeny": [],
              "omezeniObj": {"den": ""},
              "pocet": 0,
              "veta": "1",
              "cena": "40.00"
            },
            {
              "id": 1,
              "datum": "16-09.2025",
              "druh_popis": "Oběd 1",
              "delsiPopis": "Těstoviny s rajčatovou omáčkou",
              "nazev": "Těstoviny s rajčatovou omáčkou",
              "zakazaneAlergeny": null,
              "alergeny": [["01", "Obiloviny"]],
              "omezeniObj": {"den": ""},
              "pocet": "1",
              "veta": "2",
              "cena": "42,50"
            },
            {
              "id": 2,
              "datum": "17.09.2025",
              "druh_popis": "Oběd 1",
              "delsiPopis": "",
              "nazev": "Placeholder meal",
              "zakazaneAlergeny": null,
              "alergeny": [],
              "omezeniObj": {"den": ""},
              "pocet": 0,
              "veta": "3",
              "cena": "0"
            },
            {
              "id": 3,
              "datum": "17.09.2025",
              "druh_popis": "Oběd 1",
              "delsiPopis": "Prázdniny",
              "nazev": "Prázdniny",
              "zakazaneAlergeny": null,
              "alergeny": [],
              "omezeniObj": {"den": "VP"},
              "pocet": 0,
              "veta": "4",
              "cena": "0"
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(StravaCZMenuResponse.self, from: Data(json.utf8))
        let menu = StravaCZMenu.make(from: response)

        #expect(menu.days.count == 1)
        #expect(menu.days[0].dateKey == "2025-09-16")
        #expect(menu.days[0].meals.count == 1)
        #expect(menu.days[0].meals[0].id == 2)
        #expect(menu.days[0].meals[0].ordered)
        #expect(menu.days[0].meals[0].price == 42.5)
    }

    @Test func storesAndClearsStravaCZSessionSeparately() throws {
        let store = InMemoryStravaCZSessionStore()

        let saved = try store.save(loginResponse: PreviewData.stravaCZLoginResponse)

        #expect(saved.username == "student")
        #expect(saved.canteenNumber == "1234")
        #expect(try store.loadSession() == saved)

        try store.clearSession()

        #expect(try store.loadSession() == nil)
    }

    @Test func repositoryLogsInLoadsMenuAndOrdersMeal() async throws {
        let client = MockStravaCZClient()
        let sessionStore = InMemoryStravaCZSessionStore()
        let menuCache = InMemoryStravaCZMenuCache()
        let repository = StravaCZRepository(
            client: client,
            sessionStore: sessionStore,
            menuCache: menuCache
        )

        let session = try await repository.login(
            canteenNumber: "1234",
            username: "student",
            password: "secret"
        )
        let data = try await repository.loadMenu()
        let meal = try #require(data.menu.allMeals.first { $0.id == 1 })

        let orderedData = try await repository.setMeal(meal, ordered: true)

        #expect(session.username == "student")
        #expect(menuCache.cachedMenu != nil)
        #expect(client.changeMealRequests.count == 1)
        #expect(client.changeMealRequests[0].mealID == 1)
        #expect(client.changeMealRequests[0].ordered)
        #expect(orderedData.menu.allMeals.first { $0.id == 1 }?.ordered == true)
        #expect(try sessionStore.loadSession()?.balance == 60)
    }

    @Test func repositoryRollsBackWhenOrderingFails() async throws {
        let client = MockStravaCZClient(changeMealError: StravaCZAPIError.insufficientBalance(nil))
        let repository = StravaCZRepository(
            client: client,
            sessionStore: InMemoryStravaCZSessionStore(session: PreviewData.stravaCZSession),
            menuCache: InMemoryStravaCZMenuCache(
                cachedMenu: CachedStravaCZMenu(
                    menu: StravaCZMenu.make(from: PreviewData.stravaCZMenuResponse),
                    cachedAt: Date()
                )
            )
        )
        let meal = try #require(StravaCZMenu.make(from: PreviewData.stravaCZMenuResponse).allMeals.first { $0.id == 1 })

        do {
            _ = try await repository.setMeal(meal, ordered: true)
            #expect(Bool(false), "Expected ordering to fail.")
        } catch StravaCZAPIError.insufficientBalance {
            #expect(client.didCancelOrderChanges)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func repositoryClearsSessionAfterAuthenticationError() async throws {
        let sessionStore = InMemoryStravaCZSessionStore(session: PreviewData.stravaCZSession)
        let menuCache = InMemoryStravaCZMenuCache(
            cachedMenu: CachedStravaCZMenu(
                menu: StravaCZMenu.make(from: PreviewData.stravaCZMenuResponse),
                cachedAt: Date()
            )
        )
        let repository = StravaCZRepository(
            client: MockStravaCZClient(menuError: StravaCZAPIError.authentication(nil)),
            sessionStore: sessionStore,
            menuCache: menuCache
        )

        do {
            _ = try await repository.loadMenu()
            #expect(Bool(false), "Expected menu load to fail.")
        } catch StravaCZAPIError.authentication {
            #expect(try sessionStore.loadSession() == nil)
            #expect(menuCache.cachedMenu == nil)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func viewModelPromptsBeforeReplacingOrderedMeal() async throws {
        let repository = StravaCZRepository(
            client: MockStravaCZClient(),
            sessionStore: InMemoryStravaCZSessionStore(session: PreviewData.stravaCZSession),
            menuCache: InMemoryStravaCZMenuCache()
        )
        let viewModel = StravaCZViewModel(repository: repository)

        await viewModel.bootstrap()
        let firstMeal = try #require(viewModel.menu?.allMeals.first { $0.id == 1 })
        await viewModel.toggleMeal(firstMeal)

        let secondMeal = try #require(viewModel.menu?.allMeals.first { $0.id == 2 })
        await viewModel.toggleMeal(secondMeal)

        #expect(viewModel.pendingReplacement?.existingMeal.id == 1)
        #expect(viewModel.pendingReplacement?.newMeal.id == 2)
    }

    @Test func didConnectRegistersLinkedStravaCZAccount() async throws {
        let linkedAccountRepository = LinkedAccountRepository(
            store: InMemoryLinkedAccountStore(),
            client: MockLinkedAccountClient(),
            authClient: MockGradeyAuthClient()
        )
        let viewModel = StravaCZViewModel(
            repository: makeRepository(),
            linkedAccountRepository: linkedAccountRepository
        )

        await viewModel.didConnect(PreviewData.stravaCZSession)

        #expect(viewModel.phase == .signedIn)
        let linked = linkedAccountRepository.loadAccounts()
        #expect(linked.count == 1)
        #expect(linked.first?.provider == .stravaCZ)
    }

    @Test func didConnectWithoutLinkedRepositoryStillSignsIn() async throws {
        let viewModel = StravaCZViewModel(repository: makeRepository())

        await viewModel.didConnect(PreviewData.stravaCZSession)

        #expect(viewModel.phase == .signedIn)
        #expect(viewModel.session != nil)
    }

    @Test func disconnectUnlinksLinkedStravaCZAccountAndLogsOut() async throws {
        let linkedAccountRepository = LinkedAccountRepository(
            store: InMemoryLinkedAccountStore(),
            client: MockLinkedAccountClient(),
            authClient: MockGradeyAuthClient()
        )
        let client = MockStravaCZClient()
        let sessionStore = InMemoryStravaCZSessionStore(session: PreviewData.stravaCZSession)
        let viewModel = StravaCZViewModel(
            repository: StravaCZRepository(
                client: client,
                sessionStore: sessionStore,
                menuCache: InMemoryStravaCZMenuCache()
            ),
            linkedAccountRepository: linkedAccountRepository
        )

        await viewModel.didConnect(PreviewData.stravaCZSession)
        #expect(!linkedAccountRepository.loadAccounts().isEmpty)

        await viewModel.disconnect()

        #expect(viewModel.phase == .signedOut)
        #expect(linkedAccountRepository.loadAccounts().isEmpty)
        #expect(client.didLogout)
        #expect(try sessionStore.loadSession() == nil)
    }

    @Test func bootstrapResyncsPhaseWithStoredSessionOnLaterCalls() async throws {
        let sessionStore = InMemoryStravaCZSessionStore()
        let viewModel = StravaCZViewModel(
            repository: StravaCZRepository(
                client: MockStravaCZClient(),
                sessionStore: sessionStore,
                menuCache: InMemoryStravaCZMenuCache()
            )
        )

        await viewModel.bootstrap()
        #expect(viewModel.phase == .signedOut)

        // The account hub can connect behind the tab's back...
        _ = try sessionStore.save(loginResponse: PreviewData.stravaCZLoginResponse)
        await viewModel.bootstrap()
        #expect(viewModel.phase == .signedIn)

        // ...and unlink behind its back too.
        try sessionStore.clearSession()
        await viewModel.bootstrap()
        #expect(viewModel.phase == .signedOut)
    }

    private func makeRepository() -> StravaCZRepository {
        StravaCZRepository(
            client: MockStravaCZClient(),
            sessionStore: InMemoryStravaCZSessionStore(session: PreviewData.stravaCZSession),
            menuCache: InMemoryStravaCZMenuCache()
        )
    }
}

private final class InMemoryLinkedAccountStore: LinkedAccountStoring {
    private var accounts: [LinkedAccount] = []

    func loadAccounts() throws -> [LinkedAccount] {
        accounts
    }

    func saveAccounts(_ accounts: [LinkedAccount]) throws {
        self.accounts = accounts
    }

    func clearAccounts() throws {
        accounts = []
    }
}
