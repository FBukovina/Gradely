package com.bukovinafilip.gradey.data

import android.content.Context
import com.bukovinafilip.gradey.model.NotificationPreferences
import kotlinx.serialization.json.Json

class NotificationPreferencesStore internal constructor(
    private val readValue: () -> String?,
    private val writeValue: (String?) -> Unit,
    private val json: Json,
) {
    constructor(context: Context, json: Json) : this(
        readValue = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getString(STORAGE_KEY, null)
        },
        writeValue = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .apply {
                    if (value == null) remove(STORAGE_KEY) else putString(STORAGE_KEY, value)
                }
                .apply()
        },
        json = json,
    )

    var preferences: NotificationPreferences
        get() = readValue()?.let { encoded ->
            runCatching { json.decodeFromString(NotificationPreferences.serializer(), encoded) }.getOrNull()
        } ?: NotificationPreferences.Default
        set(value) = writeValue(json.encodeToString(NotificationPreferences.serializer(), value))

    fun clear() = writeValue(null)

    private companion object {
        const val PREFERENCES_NAME = "gradey-preferences"
        const val STORAGE_KEY = "gradey.notificationPreferences.v1"
    }
}
