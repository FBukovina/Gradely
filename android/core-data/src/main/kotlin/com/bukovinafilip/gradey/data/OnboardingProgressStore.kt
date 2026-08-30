package com.bukovinafilip.gradey.data

import android.content.Context
import com.bukovinafilip.gradey.model.OnboardingJourney
import com.bukovinafilip.gradey.model.OnboardingProgress
import com.bukovinafilip.gradey.model.OnboardingStep
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class OnboardingProgressStore internal constructor(
    private val readProgress: () -> String?,
    private val writeProgress: (String) -> Unit,
    private val clearProgress: () -> Unit,
    private val readCompleted: () -> Boolean,
    private val writeCompleted: (Boolean) -> Unit,
    private val json: Json,
) {
    constructor(context: Context, json: Json) : this(
        readProgress = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getString(PROGRESS_KEY, null)
        },
        writeProgress = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PROGRESS_KEY, value)
                .apply()
        },
        clearProgress = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(PROGRESS_KEY)
                .apply()
        },
        readCompleted = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(COMPLETION_KEY, false)
        },
        writeCompleted = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(COMPLETION_KEY, value)
                .apply()
        },
        json = json,
    )

    val isCompleted: Boolean get() = readCompleted()

    fun loadProgress(): OnboardingProgress? {
        val stored = readProgress() ?: return null
        runCatching { json.decodeFromString<OnboardingProgress>(stored) }
            .getOrNull()
            ?.let { return it }

        val repairedStep = when (stored.trim().trim('"')) {
            "meals" -> OnboardingStep.READY
            "welcome" -> OnboardingStep.WELCOME
            "account" -> OnboardingStep.ACCOUNT
            "school" -> OnboardingStep.SCHOOL
            "notifications" -> OnboardingStep.NOTIFICATIONS
            "ready" -> OnboardingStep.READY
            "support" -> OnboardingStep.ACCOUNT
            else -> null
        }
        if (repairedStep == null) {
            clearProgress()
            return null
        }
        return OnboardingProgress(OnboardingJourney.NEW_USER, repairedStep)
    }

    fun resolve(hasSchoolSession: Boolean): OnboardingProgress? {
        if (isCompleted) {
            clearProgress()
            return null
        }
        loadProgress()?.let { return it }
        return OnboardingProgress.initial(
            if (hasSchoolSession) OnboardingJourney.UPGRADE else OnboardingJourney.NEW_USER,
        ).also(::saveProgress)
    }

    fun saveProgress(progress: OnboardingProgress) {
        writeProgress(json.encodeToString(progress))
    }

    fun complete() {
        clearProgress()
        writeCompleted(true)
    }

    private companion object {
        const val PREFERENCES_NAME = "gradey-preferences"
        const val PROGRESS_KEY = "onboarding.progress.v2"
        const val COMPLETION_KEY = "onboarding.completed.v2"
    }
}
