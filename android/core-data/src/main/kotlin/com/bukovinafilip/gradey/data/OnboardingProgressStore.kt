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
    private val readNotificationPermissionRecovery: () -> Boolean = { false },
    private val writeNotificationPermissionRecovery: (Boolean) -> Unit = {},
    private val readNotificationPreferenceSyncPending: () -> Boolean = { false },
    private val writeNotificationPreferenceSyncPending: (Boolean) -> Unit = {},
    private val readNotificationPushRegistrationPending: () -> Boolean = { false },
    private val writeNotificationPushRegistrationPending: (Boolean) -> Unit = {},
    private val readNotificationSyncOwnerAccountID: () -> String? = { null },
    private val writeNotificationSyncOwnerAccountID: (String?) -> Unit = {},
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
        readNotificationPermissionRecovery = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(NOTIFICATION_PERMISSION_RECOVERY_KEY, false)
        },
        writeNotificationPermissionRecovery = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(NOTIFICATION_PERMISSION_RECOVERY_KEY, value)
                .commit()
        },
        readNotificationPreferenceSyncPending = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(NOTIFICATION_PREFERENCE_SYNC_PENDING_KEY, false)
        },
        writeNotificationPreferenceSyncPending = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(NOTIFICATION_PREFERENCE_SYNC_PENDING_KEY, value)
                .commit()
        },
        readNotificationPushRegistrationPending = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(NOTIFICATION_PUSH_REGISTRATION_PENDING_KEY, false)
        },
        writeNotificationPushRegistrationPending = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(NOTIFICATION_PUSH_REGISTRATION_PENDING_KEY, value)
                .commit()
        },
        readNotificationSyncOwnerAccountID = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getString(NOTIFICATION_SYNC_OWNER_ACCOUNT_ID_KEY, null)
        },
        writeNotificationSyncOwnerAccountID = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .apply {
                    if (value == null) {
                        remove(NOTIFICATION_SYNC_OWNER_ACCOUNT_ID_KEY)
                    } else {
                        putString(NOTIFICATION_SYNC_OWNER_ACCOUNT_ID_KEY, value)
                    }
                }
                .commit()
        },
    )

    val isCompleted: Boolean get() = readCompleted()

    var notificationPermissionRecoveryNeeded: Boolean
        get() = readNotificationPermissionRecovery()
        set(value) = writeNotificationPermissionRecovery(value)

    var notificationPreferenceSyncPending: Boolean
        get() = readNotificationPreferenceSyncPending()
        set(value) = writeNotificationPreferenceSyncPending(value)

    var notificationPushRegistrationPending: Boolean
        get() = readNotificationPushRegistrationPending()
        set(value) = writeNotificationPushRegistrationPending(value)

    var notificationSyncOwnerAccountID: String?
        get() = readNotificationSyncOwnerAccountID()
        set(value) = writeNotificationSyncOwnerAccountID(value?.trim()?.takeIf(String::isNotEmpty))

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
        notificationPermissionRecoveryNeeded = false
        writeCompleted(true)
    }

    fun clearNotificationRecovery() {
        notificationPermissionRecoveryNeeded = false
        notificationPreferenceSyncPending = false
        notificationPushRegistrationPending = false
        notificationSyncOwnerAccountID = null
    }

    fun restart(progress: OnboardingProgress) {
        clearNotificationRecovery()
        writeCompleted(false)
        saveProgress(progress)
    }

    private companion object {
        const val PREFERENCES_NAME = "gradey-preferences"
        const val PROGRESS_KEY = "onboarding.progress.v2"
        const val COMPLETION_KEY = "onboarding.completed.v2"
        const val NOTIFICATION_PERMISSION_RECOVERY_KEY =
            "onboarding.notificationPermissionRecovery.v1"
        const val NOTIFICATION_PREFERENCE_SYNC_PENDING_KEY =
            "onboarding.notificationPreferenceSyncPending.v1"
        const val NOTIFICATION_PUSH_REGISTRATION_PENDING_KEY =
            "onboarding.notificationPushRegistrationPending.v1"
        const val NOTIFICATION_SYNC_OWNER_ACCOUNT_ID_KEY =
            "onboarding.notificationSyncOwnerAccountID.v1"
    }
}
