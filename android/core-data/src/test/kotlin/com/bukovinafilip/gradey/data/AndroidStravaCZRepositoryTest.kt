package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.GradeyIdentityChangedException
import com.bukovinafilip.gradey.domain.StravaCZAppError
import com.bukovinafilip.gradey.domain.StravaCZAppException
import com.bukovinafilip.gradey.domain.StravaCZClient
import com.bukovinafilip.gradey.domain.StravaCZErrorKind
import com.bukovinafilip.gradey.domain.StravaCZException
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMealType
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZMenuDay
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Test

class AndroidStravaCZRepositoryTest {
    @Test
    fun `login validates fields trims identity and saves encrypted-session shape`() = runTest {
        val client = FakeStravaCZClient()
        val sessions = FakeStravaCZSessionStorage()
        val repository = repository(client, sessions)

        val missing = runCatching { repository.login("", "student", "secret") }.exceptionOrNull()
        val session = repository.login(" 1234 ", " student ", "secret")

        assertThat((missing as StravaCZAppException).error).isEqualTo(StravaCZAppError.MISSING_FIELDS)
        assertThat(client.loginRequest).isEqualTo(Triple("1234", "student", "secret"))
        assertThat(session.savedAtEpochMillis).isEqualTo(99)
        assertThat(sessions.session).isEqualTo(session)
    }

    @Test
    fun `cached menu restores before refresh and successful refresh replaces the scoped cache`() = runTest {
        val session = session()
        val sessions = FakeStravaCZSessionStorage(session)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val repository = repository(FakeStravaCZClient(menu = menu(2)), sessions, cache)
        val original = menu(1)
        cache.saveStravaMenu(scope(session), original)

        assertThat(repository.loadCachedMenu()).isEqualTo(original)
        val refreshed = repository.loadMenu(forceRefresh = true)

        assertThat(refreshed.second).isEqualTo(menu(2))
        assertThat(repository.loadCachedMenu()).isEqualTo(menu(2))
    }

    @Test
    fun `ordering updates balance saves and reloads while failure rolls back without deleting cached content`() = runTest {
        val session = session()
        val sessions = FakeStravaCZSessionStorage(session)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(menu = menu(2), changeBalance = 70.0, saveBalance = 60.0)
        val repository = repository(client, sessions, cache)

        val success = repository.setMeal(meal(1), ordered = true)
        assertThat(client.events).containsExactly("change:1:true", "save", "menu").inOrder()
        assertThat(success.first.balance).isEqualTo(60.0)
        assertThat(sessions.session?.balance).isEqualTo(60.0)

        cache.saveStravaMenu(scope(session), menu(9))
        client.events.clear()
        client.changeError = StravaCZException(StravaCZErrorKind.INSUFFICIENT_BALANCE, "low")
        val error = runCatching { repository.setMeal(meal(1), ordered = true) }.exceptionOrNull()

        assertThat((error as StravaCZException).kind).isEqualTo(StravaCZErrorKind.INSUFFICIENT_BALANCE)
        assertThat(client.events).containsExactly("change:1:true", "rollback", "menu").inOrder()
        assertThat(repository.loadCachedMenu()).isEqualTo(menu(2))
    }

    @Test
    fun `authentication failure and local logout clear only this meals session and cache`() = runTest {
        val session = session()
        val logoutGate = HeldStravaCall()
        val sessions = FakeStravaCZSessionStorage(session)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(
            menuError = StravaCZException(StravaCZErrorKind.AUTHENTICATION, "expired"),
            logoutGate = logoutGate,
        )
        val repository = repository(client, sessions, cache)
        cache.saveStravaMenu(scope(session), menu(1))

        runCatching { repository.loadMenu() }
        assertThat(sessions.session).isNull()
        assertThat(repository.loadCachedMenu()).isNull()

        sessions.session = session
        cache.saveStravaMenu(scope(session), menu(1))
        repository.logout()
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(session))).isNull()
        assertThat(logoutGate.started.isCompleted).isFalse()
        assertThat(client.events).doesNotContain("logout")
    }

    @Test
    fun `restricted and non-main meals cannot be submitted`() = runTest {
        val repository = repository(FakeStravaCZClient(), FakeStravaCZSessionStorage(session()))
        val soup = meal(1).copy(type = StravaCZMealType.SOUP)

        val error = runCatching { repository.setMeal(soup, true) }.exceptionOrNull() as StravaCZAppException

        assertThat(error.error).isEqualTo(StravaCZAppError.MEAL_NOT_MODIFIABLE)
    }

    @Test
    fun `held login cannot restore meals session after logout`() = runTest {
        val gate = HeldStravaCall()
        val sessions = FakeStravaCZSessionStorage()
        val client = FakeStravaCZClient(loginGate = gate)
        val repository = repository(client, sessions)

        val loginFailure = async {
            runCatching { repository.login("1234", "student", "secret") }.exceptionOrNull()
        }
        gate.started.await()

        repository.logout()
        assertThat(sessions.session).isNull()
        gate.release.complete(Unit)

        assertThat(loginFailure.await()).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(sessions.session).isNull()
    }

    @Test
    fun `held menu refresh cannot repopulate cache after logout`() = runTest {
        val stored = session()
        val gate = HeldStravaCall()
        val sessions = FakeStravaCZSessionStorage(stored)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(menu = menu(2), menuGate = gate)
        val repository = repository(client, sessions, cache)
        cache.saveStravaMenu(scope(stored), menu(1))

        val refreshFailure = async {
            runCatching { repository.loadMenu(forceRefresh = true) }.exceptionOrNull()
        }
        gate.started.await()

        repository.logout()
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(stored))).isNull()
        gate.release.complete(Unit)

        assertThat(refreshFailure.await()).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(stored))).isNull()
    }

    @Test
    fun `held meal mutation cannot save balance or menu after logout`() = runTest {
        val stored = session()
        val gate = HeldStravaCall()
        val sessions = FakeStravaCZSessionStorage(stored)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(
            menu = menu(2),
            changeBalance = 70.0,
            saveBalance = 60.0,
            changeGate = gate,
        )
        val repository = repository(client, sessions, cache)
        cache.saveStravaMenu(scope(stored), menu(1))

        val mutationFailure = async {
            runCatching { repository.setMeal(meal(1), ordered = true) }.exceptionOrNull()
        }
        gate.started.await()

        repository.logout()
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(stored))).isNull()
        gate.release.complete(Unit)

        assertThat(mutationFailure.await()).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(client.events).doesNotContain("save")
        assertThat(client.events).doesNotContain("menu")
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(stored))).isNull()
    }

    @Test
    fun `held failed meal mutation cannot start rollback after logout`() = runTest {
        val stored = session()
        val gate = HeldStravaCall()
        val sessions = FakeStravaCZSessionStorage(stored)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(changeGate = gate).apply {
            changeError = StravaCZException(StravaCZErrorKind.INSUFFICIENT_BALANCE, "low")
        }
        val repository = repository(client, sessions, cache)
        cache.saveStravaMenu(scope(stored), menu(1))

        val mutationFailure = async {
            runCatching { repository.setMeal(meal(1), ordered = true) }.exceptionOrNull()
        }
        gate.started.await()

        repository.logout()
        gate.release.complete(Unit)

        assertThat(mutationFailure.await()).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(client.events).containsExactly("change:1:true")
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(stored))).isNull()
    }

    @Test
    fun `held null change response cannot continue after logout`() = runTest {
        val stored = session()
        val gate = HeldStravaCall()
        val sessions = FakeStravaCZSessionStorage(stored)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(
            changeBalance = null,
            changeGate = gate,
        )
        val repository = repository(client, sessions, cache)
        cache.saveStravaMenu(scope(stored), menu(1))

        val mutationFailure = async {
            runCatching { repository.setMeal(meal(1), ordered = true) }.exceptionOrNull()
        }
        gate.started.await()

        repository.takeLocalSessionForSignOut()
        gate.release.complete(Unit)

        assertThat(mutationFailure.await()).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(client.events).containsExactly("change:1:true")
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(stored))).isNull()
    }

    @Test
    fun `held null save response cannot fetch menu after logout`() = runTest {
        val stored = session()
        val gate = HeldStravaCall()
        val sessions = FakeStravaCZSessionStorage(stored)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(
            changeBalance = 70.0,
            saveBalance = null,
            saveGate = gate,
        )
        val repository = repository(client, sessions, cache)
        cache.saveStravaMenu(scope(stored), menu(1))

        val mutationFailure = async {
            runCatching { repository.setMeal(meal(1), ordered = true) }.exceptionOrNull()
        }
        gate.started.await()

        repository.takeLocalSessionForSignOut()
        gate.release.complete(Unit)

        assertThat(mutationFailure.await()).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(client.events).containsExactly("change:1:true", "save").inOrder()
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(stored))).isNull()
    }

    @Test
    fun `held null rollback response cannot fetch menu after logout`() = runTest {
        val stored = session()
        val gate = HeldStravaCall()
        val sessions = FakeStravaCZSessionStorage(stored)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(
            rollbackBalance = null,
            rollbackGate = gate,
        ).apply {
            changeError = StravaCZException(StravaCZErrorKind.INSUFFICIENT_BALANCE, "low")
        }
        val repository = repository(client, sessions, cache)
        cache.saveStravaMenu(scope(stored), menu(1))

        val mutationFailure = async {
            runCatching { repository.setMeal(meal(1), ordered = true) }.exceptionOrNull()
        }
        gate.started.await()

        repository.takeLocalSessionForSignOut()
        gate.release.complete(Unit)

        assertThat(mutationFailure.await()).isInstanceOf(GradeyIdentityChangedException::class.java)
        assertThat(client.events).containsExactly("change:1:true", "rollback").inOrder()
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(stored))).isNull()
    }

    @Test
    fun `local sign out completes before held remote logout`() = runTest {
        val stored = session()
        val gate = HeldStravaCall()
        val sessions = FakeStravaCZSessionStorage(stored)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(logoutGate = gate)
        val repository = repository(client, sessions, cache)
        cache.saveStravaMenu(scope(stored), menu(1))

        val captured = repository.takeLocalSessionForSignOut()

        assertThat(captured).isEqualTo(stored)
        assertThat(sessions.session).isNull()
        assertThat(cache.loadStravaMenu(scope(stored))).isNull()
        assertThat(client.events).doesNotContain("logout")

        val remoteCleanup = async { repository.revokeSignedOutSession(captured!!) }
        gate.started.await()

        assertThat(remoteCleanup.isCompleted).isFalse()
        assertThat(sessions.session).isNull()
        gate.release.complete(Unit)
        remoteCleanup.await()
        assertThat(client.events).contains("logout")
    }

    private fun repository(
        client: FakeStravaCZClient,
        sessions: FakeStravaCZSessionStorage,
        cache: RoomGradeyCache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson),
    ) = AndroidStravaCZRepository(client, sessions, cache, clock = { 99 })

    private fun session() = StravaCZStoredSession(
        sessionID = "session",
        serviceURL = "https://wss5.strava.cz/service",
        canteenNumber = "1234",
        username = "student",
        balance = 100.0,
    )

    private fun meal(id: Int) = StravaCZMeal(
        id = id,
        dateKey = "2026-08-31",
        type = StravaCZMealType.MAIN,
        name = "Meal $id",
    )

    private fun menu(id: Int) = StravaCZMenu(
        listOf(StravaCZMenuDay("2026-08-31", "Monday", "2026-08-31", meals = listOf(meal(id)))),
    )

    private fun scope(session: StravaCZStoredSession): String {
        val source = "${session.serviceURL}|${session.canteenNumber}|${session.username}"
        return java.security.MessageDigest.getInstance("SHA-256")
            .digest(source.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }
}

private class FakeStravaCZSessionStorage(
    var session: StravaCZStoredSession? = null,
) : StravaCZSessionStorage {
    override fun load() = session
    override fun save(session: StravaCZStoredSession) { this.session = session }
    override fun clear() { session = null }
}

private class FakeStravaCZClient(
    var menu: StravaCZMenu = StravaCZMenu(),
    var changeBalance: Double? = 80.0,
    var saveBalance: Double? = 70.0,
    var rollbackBalance: Double? = 100.0,
    var menuError: Throwable? = null,
    var loginGate: HeldStravaCall? = null,
    var menuGate: HeldStravaCall? = null,
    var changeGate: HeldStravaCall? = null,
    var saveGate: HeldStravaCall? = null,
    var rollbackGate: HeldStravaCall? = null,
    var logoutGate: HeldStravaCall? = null,
) : StravaCZClient {
    var loginRequest: Triple<String, String, String>? = null
    var changeError: Throwable? = null
    val events = mutableListOf<String>()

    override suspend fun login(canteenNumber: String, username: String, password: String): StravaCZStoredSession {
        loginRequest = Triple(canteenNumber, username, password)
        loginGate?.awaitRelease()
        return StravaCZStoredSession("session", "https://wss5.strava.cz/service", canteenNumber, username)
    }

    override suspend fun fetchMenu(session: StravaCZStoredSession): StravaCZMenu {
        events += "menu"
        menuGate?.awaitRelease()
        menuError?.let { throw it }
        return menu
    }

    override suspend fun changeMealOrder(session: StravaCZStoredSession, mealID: Int, ordered: Boolean): Double? {
        events += "change:$mealID:$ordered"
        changeGate?.awaitRelease()
        changeError?.let { throw it }
        return changeBalance
    }

    override suspend fun saveOrders(session: StravaCZStoredSession): Double? {
        events += "save"
        saveGate?.awaitRelease()
        return saveBalance
    }

    override suspend fun cancelOrderChanges(session: StravaCZStoredSession): Double? {
        events += "rollback"
        rollbackGate?.awaitRelease()
        return rollbackBalance
    }

    override suspend fun logout(session: StravaCZStoredSession) {
        logoutGate?.awaitRelease()
        events += "logout"
    }
}

private class HeldStravaCall {
    val started = CompletableDeferred<Unit>()
    val release = CompletableDeferred<Unit>()

    suspend fun awaitRelease() {
        started.complete(Unit)
        release.await()
    }
}

private class TestCacheEntryDao : CacheEntryDao {
    private val values = mutableMapOf<String, CacheEntryEntity>()
    override suspend fun load(key: String) = values[key]
    override suspend fun save(entity: CacheEntryEntity) { values[entity.key] = entity }
    override suspend fun clear(key: String) { values.remove(key) }
    override suspend fun clearPrefix(prefix: String) { values.keys.filter { it.startsWith(prefix) }.forEach(values::remove) }
    override suspend fun clearAll() { values.clear() }
}
