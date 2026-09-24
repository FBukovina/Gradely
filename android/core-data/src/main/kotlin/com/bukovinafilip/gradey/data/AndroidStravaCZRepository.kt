package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.GradeyIdentityChangedException
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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.security.MessageDigest

class AndroidStravaCZRepository(
    private val client: StravaCZClient,
    private val sessionStore: StravaCZSessionStorage,
    private val cache: RoomGradeyCache,
    private val clock: () -> Long = System::currentTimeMillis,
) : StravaCZRepository {
    private val sessionMutationMutex = Mutex()
    private var sessionEpoch = 0L

    override suspend fun bootstrapSession(): StravaCZStoredSession? =
        sessionMutationMutex.withLock { sessionStore.load() }

    override suspend fun loadCachedMenu(): StravaCZMenu? =
        sessionMutationMutex.withLock {
            sessionStore.load()?.let { cache.loadStravaMenu(it.cacheScope()) }
        }

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
        val requestEpoch = sessionMutationMutex.withLock { sessionEpoch }
        val session = client.login(normalizedCanteen, normalizedUsername, password)
            .copy(savedAtEpochMillis = clock())
        return sessionMutationMutex.withLock {
            requireCurrentEpoch(requestEpoch)
            sessionEpoch = nextSessionEpoch(sessionEpoch)
            sessionStore.load()?.let { cache.clearStravaMenu(it.cacheScope()) }
            cache.clearStravaMenu(session.cacheScope())
            sessionStore.save(session)
            session
        }
    }

    override suspend fun loadMenu(forceRefresh: Boolean): Pair<StravaCZStoredSession, StravaCZMenu> {
        val owner = currentSessionOwner()
        return try {
            val menu = client.fetchMenu(owner.session)
            publishMenuIfCurrent(owner, menu)
            owner.session to menu
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            clearIfAuthenticationError(error, owner)
            throw error
        }
    }

    override suspend fun setMeal(
        meal: StravaCZMeal,
        ordered: Boolean,
    ): Pair<StravaCZStoredSession, StravaCZMenu> {
        if (!meal.canModify) throw StravaCZAppException(StravaCZAppError.MEAL_NOT_MODIFIABLE)
        var owner = currentSessionOwner()
        return try {
            owner = applyBalanceResponseIfCurrent(
                owner,
                client.changeMealOrder(owner.session, meal.id, ordered),
            )
            owner = applyBalanceResponseIfCurrent(
                owner,
                client.saveOrders(owner.session),
            )
            val menu = client.fetchMenu(owner.session)
            publishMenuIfCurrent(owner, menu)
            owner.session to menu
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            requireCurrentOwnerCheckpoint(owner)
            owner = rollback(owner)
            try {
                val menu = client.fetchMenu(owner.session)
                publishMenuIfCurrent(owner, menu)
            } catch (refreshCancellation: CancellationException) {
                throw refreshCancellation
            } catch (_: Throwable) {
                // Preserve the original order failure when recovery refresh is unavailable.
            }
            clearIfAuthenticationError(error, owner)
            throw error
        }
    }

    override suspend fun takeLocalSessionForSignOut(): StravaCZStoredSession? =
        sessionMutationMutex.withLock {
            sessionEpoch = nextSessionEpoch(sessionEpoch)
            val current = sessionStore.load()
            sessionStore.clear()
            current?.let { cache.clearStravaMenu(it.cacheScope()) }
            current
        }

    override suspend fun revokeSignedOutSession(session: StravaCZStoredSession) {
        try {
            client.logout(session)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // The captured session is already absent locally; remote logout is best effort.
        }
    }

    override suspend fun logout() {
        takeLocalSessionForSignOut()
    }

    private suspend fun currentSessionOwner(): SessionOwner = sessionMutationMutex.withLock {
        SessionOwner(
            epoch = sessionEpoch,
            session = sessionStore.load()
                ?: throw StravaCZAppException(StravaCZAppError.NOT_LOGGED_IN),
        )
    }

    private suspend fun persistBalanceIfCurrent(owner: SessionOwner, balance: Double): SessionOwner =
        sessionMutationMutex.withLock {
            requireCurrentOwner(owner)
            val updated = owner.session.copy(balance = balance, savedAtEpochMillis = clock())
            sessionStore.save(updated)
            owner.copy(session = updated)
        }

    private suspend fun applyBalanceResponseIfCurrent(
        owner: SessionOwner,
        balance: Double?,
    ): SessionOwner = if (balance == null) {
        requireCurrentOwnerCheckpoint(owner)
        owner
    } else {
        persistBalanceIfCurrent(owner, balance)
    }

    private suspend fun publishMenuIfCurrent(owner: SessionOwner, menu: StravaCZMenu) {
        sessionMutationMutex.withLock {
            requireCurrentOwner(owner)
            cache.saveStravaMenu(owner.session.cacheScope(), menu)
        }
    }

    private suspend fun rollback(owner: SessionOwner): SessionOwner =
        try {
            applyBalanceResponseIfCurrent(
                owner,
                client.cancelOrderChanges(owner.session),
            )
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Preserve the original order error when rollback is unavailable.
            requireCurrentOwnerCheckpoint(owner)
            owner
        }

    private suspend fun requireCurrentOwnerCheckpoint(owner: SessionOwner) {
        sessionMutationMutex.withLock { requireCurrentOwner(owner) }
    }

    private suspend fun clearIfAuthenticationError(error: Throwable, owner: SessionOwner) {
        if (error is StravaCZException && error.kind == StravaCZErrorKind.AUTHENTICATION) {
            sessionMutationMutex.withLock {
                if (!owner.isCurrent()) return@withLock
                sessionEpoch = nextSessionEpoch(sessionEpoch)
                sessionStore.clear()
                cache.clearStravaMenu(owner.session.cacheScope())
            }
        }
    }

    private fun requireCurrentEpoch(expectedEpoch: Long) {
        if (sessionEpoch != expectedEpoch) throw GradeyIdentityChangedException()
    }

    private fun requireCurrentOwner(owner: SessionOwner) {
        if (!owner.isCurrent()) throw GradeyIdentityChangedException()
    }

    private fun SessionOwner.isCurrent(): Boolean =
        epoch == sessionEpoch && sessionStore.load() == session

    private fun nextSessionEpoch(current: Long): Long =
        if (current == Long.MAX_VALUE) Long.MIN_VALUE else current + 1L

    private data class SessionOwner(
        val epoch: Long,
        val session: StravaCZStoredSession,
    )
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
