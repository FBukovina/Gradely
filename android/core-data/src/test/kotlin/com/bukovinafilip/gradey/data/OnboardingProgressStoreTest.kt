package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.OnboardingJourney
import com.bukovinafilip.gradey.model.OnboardingProgress
import com.bukovinafilip.gradey.model.OnboardingStep
import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.json.Json
import org.junit.Test

class OnboardingProgressStoreTest {
    @Test
    fun `new install starts and resumes the new-user welcome`() {
        val backend = Backend()
        val store = backend.store()

        val initial = store.resolve(hasSchoolSession = false)

        assertThat(initial).isEqualTo(
            OnboardingProgress(OnboardingJourney.NEW_USER, OnboardingStep.WELCOME),
        )
        assertThat(store.loadProgress()).isEqualTo(initial)

        val advanced = initial!!.copy(step = OnboardingStep.SCHOOL)
        store.saveProgress(advanced)
        assertThat(backend.store().resolve(hasSchoolSession = false)).isEqualTo(advanced)
    }

    @Test
    fun `existing school session starts the non-destructive upgrade journey`() {
        val store = Backend().store()

        assertThat(store.resolve(hasSchoolSession = true)).isEqualTo(
            OnboardingProgress(OnboardingJourney.UPGRADE, OnboardingStep.WELCOME),
        )
    }

    @Test
    fun `completion clears progress and prevents restart loops`() {
        val backend = Backend()
        val store = backend.store()
        store.resolve(hasSchoolSession = false)

        store.complete()

        assertThat(store.isCompleted).isTrue()
        assertThat(store.loadProgress()).isNull()
        assertThat(backend.store().resolve(hasSchoolSession = false)).isNull()
    }

    @Test
    fun `hidden debug restart reopens the requested journey after completion`() {
        val backend = Backend(completed = true)
        val store = backend.store()
        val restarted = OnboardingProgress(OnboardingJourney.UPGRADE, OnboardingStep.WELCOME)

        store.restart(restarted)

        assertThat(store.isCompleted).isFalse()
        assertThat(backend.store().resolve(hasSchoolSession = true)).isEqualTo(restarted)
    }

    @Test
    fun `legacy step-only progress is repaired and corrupt progress is cleared`() {
        val backend = Backend(progress = "meals")
        assertThat(backend.store().loadProgress()).isEqualTo(
            OnboardingProgress(OnboardingJourney.NEW_USER, OnboardingStep.READY),
        )

        backend.progress = "{broken"
        assertThat(backend.store().loadProgress()).isNull()
        assertThat(backend.progress).isNull()
    }

    @Test
    fun `notification recovery state survives recreation and restart clears it`() {
        val backend = Backend()
        val store = backend.store()
        store.notificationPermissionRecoveryNeeded = true
        store.notificationPreferenceSyncPending = true
        store.notificationPushRegistrationPending = true
        store.notificationSyncOwnerAccountID = " account-a "

        assertThat(backend.store().notificationPermissionRecoveryNeeded).isTrue()
        assertThat(backend.store().notificationPreferenceSyncPending).isTrue()
        assertThat(backend.store().notificationPushRegistrationPending).isTrue()
        assertThat(backend.store().notificationSyncOwnerAccountID).isEqualTo("account-a")

        store.complete()
        assertThat(backend.store().notificationPermissionRecoveryNeeded).isFalse()
        assertThat(backend.store().notificationPreferenceSyncPending).isTrue()
        assertThat(backend.store().notificationPushRegistrationPending).isTrue()
        assertThat(backend.store().notificationSyncOwnerAccountID).isEqualTo("account-a")

        store.clearNotificationRecovery()
        assertThat(backend.store().notificationPermissionRecoveryNeeded).isFalse()
        assertThat(backend.store().notificationPreferenceSyncPending).isFalse()
        assertThat(backend.store().notificationPushRegistrationPending).isFalse()
        assertThat(backend.store().notificationSyncOwnerAccountID).isNull()

        store.notificationPermissionRecoveryNeeded = true
        store.notificationPreferenceSyncPending = true
        store.notificationPushRegistrationPending = true
        store.notificationSyncOwnerAccountID = "account-b"
        store.restart(OnboardingProgress(OnboardingJourney.NEW_USER, OnboardingStep.WELCOME))
        assertThat(backend.store().notificationPermissionRecoveryNeeded).isFalse()
        assertThat(backend.store().notificationPreferenceSyncPending).isFalse()
        assertThat(backend.store().notificationPushRegistrationPending).isFalse()
        assertThat(backend.store().notificationSyncOwnerAccountID).isNull()
    }

    private class Backend(
        var progress: String? = null,
        var completed: Boolean = false,
        var notificationPermissionRecoveryNeeded: Boolean = false,
        var notificationPreferenceSyncPending: Boolean = false,
        var notificationPushRegistrationPending: Boolean = false,
        var notificationSyncOwnerAccountID: String? = null,
    ) {
        fun store() = OnboardingProgressStore(
            readProgress = { progress },
            writeProgress = { progress = it },
            clearProgress = { progress = null },
            readCompleted = { completed },
            writeCompleted = { completed = it },
            json = Json { ignoreUnknownKeys = true },
            readNotificationPermissionRecovery = { notificationPermissionRecoveryNeeded },
            writeNotificationPermissionRecovery = { notificationPermissionRecoveryNeeded = it },
            readNotificationPreferenceSyncPending = { notificationPreferenceSyncPending },
            writeNotificationPreferenceSyncPending = { notificationPreferenceSyncPending = it },
            readNotificationPushRegistrationPending = { notificationPushRegistrationPending },
            writeNotificationPushRegistrationPending = { notificationPushRegistrationPending = it },
            readNotificationSyncOwnerAccountID = { notificationSyncOwnerAccountID },
            writeNotificationSyncOwnerAccountID = { notificationSyncOwnerAccountID = it },
        )
    }
}
