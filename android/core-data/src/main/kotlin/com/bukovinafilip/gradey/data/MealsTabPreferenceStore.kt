package com.bukovinafilip.gradey.data

import android.content.Context

class MealsTabPreferenceStore internal constructor(
    private val readVisible: () -> Boolean,
    private val writeVisible: (Boolean) -> Unit,
) {
    constructor(context: Context) : this(
        readVisible = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(VISIBLE_KEY, true)
        },
        writeVisible = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(VISIBLE_KEY, value)
                .apply()
        },
    )

    var isVisible: Boolean
        get() = readVisible()
        set(value) = writeVisible(value)

    private companion object {
        const val PREFERENCES_NAME = "gradey-preferences"
        const val VISIBLE_KEY = "settings.showMealsTab"
    }
}
