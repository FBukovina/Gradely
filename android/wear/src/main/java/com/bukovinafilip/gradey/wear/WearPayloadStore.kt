package com.bukovinafilip.gradey.wear

import android.content.Context
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json

class WearPayloadStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val mutablePayload = MutableStateFlow(decode(preferences.getString(PAYLOAD_KEY, null)))

    val payload: StateFlow<GradeyWearSyncPayload?> = mutablePayload.asStateFlow()

    fun update(encoded: ByteArray): Boolean {
        val raw = encoded.decodeToString()
        val decoded = decode(raw) ?: return false
        preferences.edit().putString(PAYLOAD_KEY, raw).apply()
        mutablePayload.value = decoded
        return true
    }

    fun clear() {
        preferences.edit().remove(PAYLOAD_KEY).apply()
        mutablePayload.value = null
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
        val JsonCodec = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            explicitNulls = false
        }
    }
}
