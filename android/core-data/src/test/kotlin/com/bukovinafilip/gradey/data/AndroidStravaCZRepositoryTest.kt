package com.bukovinafilip.gradey.data

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
    fun `authentication failure and logout clear only this meals session and cache`() = runTest {
        val session = session()
        val sessions = FakeStravaCZSessionStorage(session)
        val cache = RoomGradeyCache(TestCacheEntryDao(), GradeyJson)
        val client = FakeStravaCZClient(
            menuError = StravaCZException(StravaCZErrorKind.AUTHENTICATION, "expired"),
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
        assertThat(client.events).contains("logout")
    }

    @Test
    fun `restricted and non-main meals cannot be submitted`() = runTest {
        val repository = repository(FakeStravaCZClient(), FakeStravaCZSessionStorage(session()))
        val soup = meal(1).copy(type = StravaCZMealType.SOUP)

        val error = runCatching { repository.setMeal(soup, true) }.exceptionOrNull() as StravaCZAppException

        assertThat(error.error).isEqualTo(StravaCZAppError.MEAL_NOT_MODIFIABLE)
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
    var menuError: Throwable? = null,
) : StravaCZClient {
    var loginRequest: Triple<String, String, String>? = null
    var changeError: Throwable? = null
    val events = mutableListOf<String>()

    override suspend fun login(canteenNumber: String, username: String, password: String): StravaCZStoredSession {
        loginRequest = Triple(canteenNumber, username, password)
        return StravaCZStoredSession("session", "https://wss5.strava.cz/service", canteenNumber, username)
    }

    override suspend fun fetchMenu(session: StravaCZStoredSession): StravaCZMenu {
        events += "menu"
        menuError?.let { throw it }
        return menu
    }

    override suspend fun changeMealOrder(session: StravaCZStoredSession, mealID: Int, ordered: Boolean): Double? {
        events += "change:$mealID:$ordered"
        changeError?.let { throw it }
        return changeBalance
    }

    override suspend fun saveOrders(session: StravaCZStoredSession): Double? {
        events += "save"
        return saveBalance
    }

    override suspend fun cancelOrderChanges(session: StravaCZStoredSession): Double? {
        events += "rollback"
        return 100.0
    }

    override suspend fun logout(session: StravaCZStoredSession) {
        events += "logout"
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
