package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.StravaCZAppError
import com.bukovinafilip.gradey.domain.StravaCZAppException
import com.bukovinafilip.gradey.domain.StravaCZClient
import com.bukovinafilip.gradey.domain.StravaCZErrorKind
import com.bukovinafilip.gradey.domain.StravaCZException
import com.bukovinafilip.gradey.domain.StravaCZRepository
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import kotlinx.coroutines.CancellationException
import java.security.MessageDigest

class AndroidStravaCZRepository(
    private val client: StravaCZClient,
    private val sessionStore: StravaCZSessionStorage,
    private val cache: RoomGradeyCache,
    private val clock: () -> Long = System::currentTimeMillis,
) : StravaCZRepository {
    override suspend fun bootstrapSession(): StravaCZStoredSession? = sessionStore.load()

    override suspend fun loadCachedMenu(): StravaCZMenu? =
        sessionStore.load()?.let { cache.loadStravaMenu(it.cacheScope()) }

    override suspend fun login(
        canteenNumber: String,
        username: String,
        password: String,
    ): StravaCZStoredSession {
        val normalizedCanteen = canteenNumber.trim()
        val normalizedUsername = username.trim()
        if (normalizedCanteen.isEmpty() || normalizedUsername.isEmpty() || password.isEmpty()) {
            throw StravaCZAppException(StravaCZAppError.MISSING_FIELDS)
        }
        val previous = sessionStore.load()
        val session = client.login(normalizedCanteen, normalizedUsername, password)
            .copy(savedAtEpochMillis = clock())
        previous?.let { cache.clearStravaMenu(it.cacheScope()) }
        cache.clearStravaMenu(session.cacheScope())
        sessionStore.save(session)
        return session
    }

    override suspend fun loadMenu(forceRefresh: Boolean): Pair<StravaCZStoredSession, StravaCZMenu> {
        val session = validSession()
        return try {
            val menu = client.fetchMenu(session)
            cache.saveStravaMenu(session.cacheScope(), menu)
            session to menu
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            clearIfAuthenticationError(error, session)
            throw error
        }
    }

    override suspend fun setMeal(
        meal: StravaCZMeal,
        ordered: Boolean,
    ): Pair<StravaCZStoredSession, StravaCZMenu> {
        if (!meal.canModify) throw StravaCZAppException(StravaCZAppError.MEAL_NOT_MODIFIABLE)
        var session = validSession()
        return try {
            client.changeMealOrder(session, meal.id, ordered)?.let { balance ->
                session = session.copy(balance = balance, savedAtEpochMillis = clock())
                sessionStore.save(session)
            }
            client.saveOrders(session)?.let { balance ->
                session = session.copy(balance = balance, savedAtEpochMillis = clock())
                sessionStore.save(session)
            }
            val menu = client.fetchMenu(session)
            cache.saveStravaMenu(session.cacheScope(), menu)
            session to menu
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            rollback(session)
            runCatching {
                val menu = client.fetchMenu(session)
                cache.saveStravaMenu(session.cacheScope(), menu)
            }
            clearIfAuthenticationError(error, session)
            throw error
        }
    }

    override suspend fun logout() {
        val session = sessionStore.load()
        sessionStore.clear()
        session?.let { cache.clearStravaMenu(it.cacheScope()) }
        if (session != null) {
            try {
                client.logout(session)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Local disconnect is authoritative; remote logout is best effort.
            }
        }
    }

    private fun validSession(): StravaCZStoredSession = sessionStore.load()
        ?: throw StravaCZAppException(StravaCZAppError.NOT_LOGGED_IN)

    private suspend fun rollback(session: StravaCZStoredSession) {
        try {
            val balance = client.cancelOrderChanges(session) ?: return
            sessionStore.save(session.copy(balance = balance, savedAtEpochMillis = clock()))
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Preserve the original order error when rollback is unavailable.
        }
    }

    private suspend fun clearIfAuthenticationError(error: Throwable, session: StravaCZStoredSession) {
        if (error is StravaCZException && error.kind == StravaCZErrorKind.AUTHENTICATION) {
            sessionStore.clear()
            cache.clearStravaMenu(session.cacheScope())
        }
    }
}

interface StravaCZSessionStorage {
    fun load(): StravaCZStoredSession?
    fun save(session: StravaCZStoredSession)
    fun clear()
}

class StravaCZSessionStore(
    private val secureJsonStore: SecureJsonStore,
) : StravaCZSessionStorage {
    override fun load(): StravaCZStoredSession? =
        secureJsonStore.loadOrClearInvalid(KEY, StravaCZStoredSession.serializer())

    override fun save(session: StravaCZStoredSession) =
        secureJsonStore.save(KEY, session, StravaCZStoredSession.serializer())

    override fun clear() = secureJsonStore.clear(KEY)

    private companion object {
        const val KEY = "stravacz.session.v1"
    }
}

private fun StravaCZStoredSession.cacheScope(): String {
    val source = "$serviceURL|$canteenNumber|$username"
    return MessageDigest.getInstance("SHA-256")
        .digest(source.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
