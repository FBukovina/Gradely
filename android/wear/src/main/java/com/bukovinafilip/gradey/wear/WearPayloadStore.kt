package com.bukovinafilip.gradey.wear

import android.content.ComponentName
import android.content.Context
import androidx.core.content.edit
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json

class WearPayloadStore(context: Context) {
    private val applicationContext = context.applicationContext
    private val preferences = applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val mutablePayload = MutableStateFlow(decode(preferences.getString(PAYLOAD_KEY, null)))
    private var currentSourceID = preferences.getString(PAYLOAD_SOURCE_KEY, null)
    private val complicationUpdateRequester by lazy {
        ComplicationDataSourceUpdateRequester.create(
            applicationContext,
            ComponentName(applicationContext, GradeyComplicationDataSourceService::class.java),
        )
    }

    val payload: StateFlow<GradeyWearSyncPayload?> = mutablePayload.asStateFlow()

    @Synchronized
    internal fun update(encoded: ByteArray, sourceID: String?): WearPayloadUpdateResult {
        val raw = runCatching(encoded::decodeToString).getOrNull()
            ?: return WearPayloadUpdateResult.INVALID
        val decoded = decode(raw) ?: return WearPayloadUpdateResult.INVALID
        if (selectFreshestWearPayload(mutablePayload.value, decoded) !== decoded) {
            return WearPayloadUpdateResult.RETAINED_NEWER
        }
        preferences.edit {
            putString(PAYLOAD_KEY, raw)
            if (sourceID == null) remove(PAYLOAD_SOURCE_KEY) else putString(PAYLOAD_SOURCE_KEY, sourceID)
        }
        currentSourceID = sourceID
        mutablePayload.value = decoded
        complicationUpdateRequester.requestUpdateAll()
        return WearPayloadUpdateResult.APPLIED
    }

    @Synchronized
    internal fun deleteSource(sourceID: String?): Boolean {
        if (!shouldClearWearPayloadForDeletedSource(currentSourceID, sourceID)) return false
        clearLocked()
        return true
    }

    @Synchronized
    internal fun retainOnlySources(sourceIDs: Set<String>): Boolean {
        mutablePayload.value ?: return false
        if (shouldRetainWearPayloadForSources(currentSourceID, sourceIDs)) return false
        clearLocked()
        return true
    }

    private fun clearLocked() {
        preferences.edit {
            remove(PAYLOAD_KEY)
            remove(PAYLOAD_SOURCE_KEY)
        }
        currentSourceID = null
        mutablePayload.value = null
        complicationUpdateRequester.requestUpdateAll()
    }

    private fun decode(raw: String?): GradeyWearSyncPayload? {
        if (raw.isNullOrBlank()) return null
        val payload = runCatching {
            JsonCodec.decodeFromString(GradeyWearSyncPayload.serializer(), raw)
        }.getOrNull() ?: return null
        return payload.takeIf { it.schemaVersion == GradeyWearSyncPayload.CURRENT_SCHEMA_VERSION }
    }

    private companion object {
        const val PREFERENCES_NAME = "gradey-wear-sync"
        const val PAYLOAD_KEY = "payload.v3"
        const val PAYLOAD_SOURCE_KEY = "payload-source.v1"
        val JsonCodec = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            explicitNulls = false
        }
    }
}

internal fun shouldClearWearPayloadForDeletedSource(
    currentSourceID: String?,
    deletedSourceID: String?,
): Boolean = currentSourceID == null || deletedSourceID == null || currentSourceID == deletedSourceID

internal fun shouldRetainWearPayloadForSources(
    currentSourceID: String?,
    availableSourceIDs: Set<String>,
): Boolean = currentSourceID != null && currentSourceID in availableSourceIDs

internal enum class WearPayloadUpdateResult {
    APPLIED,
    RETAINED_NEWER,
    INVALID,
}

/**
 * Data Items from more than one paired node are not ordered. Keep the newest phone projection even
 * when an older item is delivered after it. New phone versions publish monotonic generations, but
 * equal legacy generations prefer signed-out state so delivery order cannot restore private data.
 */
internal fun selectFreshestWearPayload(
    current: GradeyWearSyncPayload?,
    incoming: GradeyWearSyncPayload,
): GradeyWearSyncPayload = when {
    current == null -> incoming
    current.generatedAtEpochMillis > incoming.generatedAtEpochMillis -> current
    current.generatedAtEpochMillis < incoming.generatedAtEpochMillis -> incoming
    !current.isSignedIn && incoming.isSignedIn -> current
    else -> incoming
}
