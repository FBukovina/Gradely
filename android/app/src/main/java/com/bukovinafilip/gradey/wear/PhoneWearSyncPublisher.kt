package com.bukovinafilip.gradey.wear

import android.annotation.SuppressLint
import android.content.Context
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.domain.WearPayloadBuilder
import com.bukovinafilip.gradey.model.GradeyWearSyncContract
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.model.UserResponse
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

object PhoneWearSyncPublisher {
    suspend fun publish(
        context: Context,
        payload: GradeyWearSyncPayload,
        isStillCurrent: suspend () -> Boolean = { true },
    ): Boolean = publishCoordinator.runIf(isStillCurrent) {
        val applicationContext = context.applicationContext
        val versionedPayload = withContext(Dispatchers.IO) {
            payload.withMonotonicGeneration(applicationContext)
        }
        val encoded = GradeyJson.encodeToString(GradeyWearSyncPayload.serializer(), versionedPayload)
            .encodeToByteArray()
        require(encoded.size <= MAX_DATA_ITEM_BYTES) { "Wear sync payload is too large." }

        val request = PutDataMapRequest.create(GradeyWearSyncContract.DATA_PATH).apply {
            dataMap.putByteArray(GradeyWearSyncContract.PAYLOAD_KEY, encoded)
            dataMap.putLong(GradeyWearSyncContract.GENERATED_AT_KEY, versionedPayload.generatedAtEpochMillis)
        }.asPutDataRequest().setUrgent()

        val task = Wearable.getDataClient(applicationContext).putDataItem(request)
        try {
            task.await()
        } catch (error: CancellationException) {
            // Task.await() cannot cancel this Play services write. Drain it before allowing the next
            // generation to publish, then preserve structured cancellation for the caller.
            withContext(NonCancellable) { runCatching { task.await() } }
            throw error
        }
    }

    @SuppressLint("ApplySharedPref")
    private fun GradeyWearSyncPayload.withMonotonicGeneration(context: Context): GradeyWearSyncPayload {
        val preferences = context.getSharedPreferences(GENERATION_PREFERENCES_NAME, Context.MODE_PRIVATE)
        val previous = if (preferences.contains(LAST_GENERATION_KEY)) {
            preferences.getLong(LAST_GENERATION_KEY, generatedAtEpochMillis)
        } else {
            null
        }
        val generation = nextWearPayloadGeneration(previous, generatedAtEpochMillis)
        check(preferences.edit().putLong(LAST_GENERATION_KEY, generation).commit()) {
            "Could not persist the Wear sync generation."
        }
        return copy(generatedAtEpochMillis = generation)
    }

    private const val MAX_DATA_ITEM_BYTES = 100 * 1024
    private const val GENERATION_PREFERENCES_NAME = "gradey-wear-sync-publisher"
    private const val LAST_GENERATION_KEY = "last-generation.v1"
    private val publishCoordinator = WearPublishCoordinator()
}

internal suspend fun publishCredentialFreeWearState(
    publicationSession: StoredSession,
    displayedTimetable: TimetableWeek?,
    cachedCurrentTimetable: TimetableWeek?,
    user: UserResponse?,
    supportTier: GradeySupportTier,
    currentSession: suspend () -> StoredSession?,
    isStillCurrent: suspend () -> Boolean = { true },
    today: LocalDate = TimetableDates.today(),
    publish: suspend (
        payload: GradeyWearSyncPayload,
        isStillCurrent: suspend () -> Boolean,
    ) -> Boolean,
): Boolean {
    val currentTimetable = WearPayloadBuilder.currentWeekProjection(
        preferred = displayedTimetable,
        cachedCurrent = cachedCurrentTimetable,
        today = today,
    )
    val payload = WearPayloadBuilder.signedIn(
        week = currentTimetable,
        user = user,
        supportTier = supportTier,
    )
    check(payload.auth == null) { "Phone-to-watch snapshots must not contain school credentials." }
    return publish(payload) {
        isStillCurrent() && currentSession()?.cacheScope == publicationSession.cacheScope
    }
}

internal suspend fun loadCurrentWearTimetableCacheWhenNeeded(
    displayedTimetable: TimetableWeek?,
    today: LocalDate = TimetableDates.today(),
    loadCachedTimetable: suspend (weekStart: String) -> TimetableWeek?,
): TimetableWeek? {
    if (WearPayloadBuilder.currentWeekProjection(displayedTimetable, null, today) != null) {
        return null
    }
    return loadCachedTimetable(
        TimetableDates.apiDateString(TimetableDates.monday(today)),
    )
}

internal fun nextWearPayloadGeneration(previous: Long?, requested: Long): Long = when (previous) {
    null -> requested
    Long.MAX_VALUE -> Long.MAX_VALUE
    else -> maxOf(requested, previous + 1)
}

internal class WearPublishCoordinator {
    private val mutex = Mutex()

    suspend fun runIf(
        isStillCurrent: suspend () -> Boolean,
        block: suspend () -> Unit,
    ): Boolean {
        mutex.lock()
        try {
            if (!isStillCurrent()) return false
            block()
            return true
        } finally {
            mutex.unlock()
        }
    }

    suspend fun <T> run(block: suspend () -> T): T {
        mutex.lock()
        try {
            return block()
        } finally {
            mutex.unlock()
        }
    }
}
