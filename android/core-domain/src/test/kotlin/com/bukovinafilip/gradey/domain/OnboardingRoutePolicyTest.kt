package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.OnboardingJourney
import com.bukovinafilip.gradey.model.OnboardingProgress
import com.bukovinafilip.gradey.model.OnboardingStep
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class OnboardingRoutePolicyTest {
    @Test
    fun `interrupted new-user flow repairs itself from durable account and school state`() {
        val account = progress(OnboardingJourney.NEW_USER, OnboardingStep.ACCOUNT)
        assertThat(reconcile(account, guest = false, auth = false, school = false).step)
            .isEqualTo(OnboardingStep.ACCOUNT)
        assertThat(reconcile(account, guest = true, auth = false, school = false).step)
            .isEqualTo(OnboardingStep.SCHOOL)
        assertThat(reconcile(account, guest = true, auth = false, school = true).step)
            .isEqualTo(OnboardingStep.READY)
        assertThat(reconcile(account, guest = false, auth = true, school = true).step)
            .isEqualTo(OnboardingStep.NOTIFICATIONS)
    }

    @Test
    fun `missing durable prerequisites move a stale saved step backward safely`() {
        val ready = progress(OnboardingJourney.NEW_USER, OnboardingStep.READY)
        assertThat(reconcile(ready, guest = false, auth = false, school = true).step)
            .isEqualTo(OnboardingStep.ACCOUNT)
        assertThat(reconcile(ready, guest = true, auth = false, school = false).step)
            .isEqualTo(OnboardingStep.SCHOOL)
    }

    @Test
    fun `upgrade journey never asks an existing school to reconnect`() {
        val account = progress(OnboardingJourney.UPGRADE, OnboardingStep.ACCOUNT)
        assertThat(reconcile(account, guest = true, auth = false, school = true).step)
            .isEqualTo(OnboardingStep.SUPPORT)
        assertThat(reconcile(account, guest = false, auth = true, school = true).step)
            .isEqualTo(OnboardingStep.SUPPORT)
    }

    private fun progress(journey: OnboardingJourney, step: OnboardingStep) =
        OnboardingProgress(journey, step)

    private fun reconcile(
        progress: OnboardingProgress,
        guest: Boolean,
        auth: Boolean,
        school: Boolean,
    ) = reconcileOnboardingProgress(progress, guest, auth, school)
}
