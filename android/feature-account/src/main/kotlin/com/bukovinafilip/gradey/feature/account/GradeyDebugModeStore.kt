package com.bukovinafilip.gradey.feature.account

import android.content.Context

internal data class DebugVersionTapResult(
    val tapCount: Int,
    val unlocked: Boolean,
)

/** Keeps the hidden debug-panel opt-in across process restarts without storing diagnostics. */
internal class GradeyDebugModeStore internal constructor(
    private val readEnabled: () -> Boolean,
    private val writeEnabled: (Boolean) -> Unit,
) {
    constructor(context: Context) : this(
        readEnabled = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(ENABLED_KEY, false)
        },
        writeEnabled = { enabled ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(ENABLED_KEY, enabled)
                .apply()
        },
    )

    var isEnabled: Boolean
        get() = readEnabled()
        set(value) = writeEnabled(value)

    fun registerVersionTap(currentTapCount: Int): DebugVersionTapResult {
        val nextTapCount = currentTapCount + 1
        if (nextTapCount < REQUIRED_TAP_COUNT) {
            return DebugVersionTapResult(tapCount = nextTapCount, unlocked = false)
        }

        isEnabled = true
        return DebugVersionTapResult(tapCount = 0, unlocked = true)
    }

    internal companion object {
        const val REQUIRED_TAP_COUNT = 7
        private const val PREFERENCES_NAME = "gradey-preferences"
        private const val ENABLED_KEY = "gradey.debugMode.enabled.v1"
    }
}
