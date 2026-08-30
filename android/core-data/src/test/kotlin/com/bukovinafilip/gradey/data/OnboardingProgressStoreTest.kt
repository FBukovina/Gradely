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
    fun `legacy step-only progress is repaired and corrupt progress is cleared`() {
        val backend = Backend(progress = "meals")
        assertThat(backend.store().loadProgress()).isEqualTo(
            OnboardingProgress(OnboardingJourney.NEW_USER, OnboardingStep.READY),
        )

        backend.progress = "{broken"
        assertThat(backend.store().loadProgress()).isNull()
        assertThat(backend.progress).isNull()
    }

    private class Backend(
        var progress: String? = null,
        var completed: Boolean = false,
    ) {
        fun store() = OnboardingProgressStore(
            readProgress = { progress },
            writeProgress = { progress = it },
            clearProgress = { progress = null },
            readCompleted = { completed },
            writeCompleted = { completed = it },
            json = Json { ignoreUnknownKeys = true },
        )
    }
}
