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
    private val complicationUpdateRequester by lazy {
        ComplicationDataSourceUpdateRequester.create(
            applicationContext,
            ComponentName(applicationContext, GradeyComplicationDataSourceService::class.java),
        )
    }

    val payload: StateFlow<GradeyWearSyncPayload?> = mutablePayload.asStateFlow()

    fun update(encoded: ByteArray): Boolean {
        val raw = encoded.decodeToString()
        val decoded = decode(raw) ?: return false
        preferences.edit { putString(PAYLOAD_KEY, raw) }
        mutablePayload.value = decoded
        complicationUpdateRequester.requestUpdateAll()
        return true
    }

    fun clear() {
        preferences.edit { remove(PAYLOAD_KEY) }
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
        val JsonCodec = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            explicitNulls = false
        }
    }
}
