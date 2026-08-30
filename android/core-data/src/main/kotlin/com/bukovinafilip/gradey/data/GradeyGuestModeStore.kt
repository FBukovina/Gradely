package com.bukovinafilip.gradey.data

import android.content.Context

class GradeyGuestModeStore internal constructor(
    private val readEnabled: () -> Boolean,
    private val writeEnabled: (Boolean) -> Unit,
) {
    constructor(context: Context) : this(
        readEnabled = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(ENABLED_KEY, false)
        },
        writeEnabled = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(ENABLED_KEY, value)
                .apply()
        },
    )

    var isEnabled: Boolean
        get() = readEnabled()
        set(value) = writeEnabled(value)

    private companion object {
        const val PREFERENCES_NAME = "gradey-preferences"
        const val ENABLED_KEY = "gradey.guestMode.enabled.v1"
    }
}
