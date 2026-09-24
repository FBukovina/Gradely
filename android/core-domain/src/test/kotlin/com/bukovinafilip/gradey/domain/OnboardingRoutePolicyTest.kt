package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
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

    @Test
    fun `new user skips notification prompt until school cloud link succeeds`() {
        val school = progress(OnboardingJourney.NEW_USER, OnboardingStep.SCHOOL)
        assertThat(reconcile(school, guest = false, auth = true, school = true, cloudLinked = false).step)
            .isEqualTo(OnboardingStep.READY)
        assertThat(reconcile(school, guest = false, auth = true, school = true, cloudLinked = true).step)
            .isEqualTo(OnboardingStep.NOTIFICATIONS)

        val notifications = progress(OnboardingJourney.NEW_USER, OnboardingStep.NOTIFICATIONS)
        assertThat(reconcile(notifications, guest = false, auth = true, school = true, cloudLinked = false).step)
            .isEqualTo(OnboardingStep.READY)
    }

    @Test
    fun `ready cloud warning is reconstructed only for an unlinked Gradey ID school`() {
        val ready = progress(OnboardingJourney.NEW_USER, OnboardingStep.READY)
        assertThat(shouldShowOnboardingSchoolCloudLinkWarning(ready, false, true, true, false)).isTrue()
        assertThat(shouldShowOnboardingSchoolCloudLinkWarning(ready, false, true, true, true)).isFalse()
        assertThat(shouldShowOnboardingSchoolCloudLinkWarning(ready, true, false, true, false)).isFalse()
        assertThat(shouldShowOnboardingSchoolCloudLinkWarning(ready, false, false, true, false)).isFalse()
        assertThat(
            shouldShowOnboardingSchoolCloudLinkWarning(
                progress(OnboardingJourney.NEW_USER, OnboardingStep.SCHOOL),
                false,
                true,
                true,
                false,
            ),
        ).isFalse()
    }

    @Test
    fun `current school cloud link trusts offline association but rejects stale refreshed IDs`() {
        val current = linkedAccount("current", LinkedAccountProvider.BAKALARI)
        val other = linkedAccount("other", LinkedAccountProvider.BAKALARI)
        val meals = linkedAccount("current", LinkedAccountProvider.STRAVA_CZ)
        val reconnecting = linkedAccount(
            "current",
            LinkedAccountProvider.BAKALARI,
            LinkedAccountStatus.ACTION_REQUIRED,
        )

        assertThat(isCurrentSchoolCloudLinked("current", null)).isTrue()
        assertThat(isCurrentSchoolCloudLinked("current", listOf(current))).isTrue()
        assertThat(isCurrentSchoolCloudLinked("current", listOf(other))).isFalse()
        assertThat(isCurrentSchoolCloudLinked("current", listOf(meals))).isFalse()
        assertThat(isCurrentSchoolCloudLinked("current", listOf(reconnecting))).isFalse()
        assertThat(isCurrentSchoolCloudLinked(null, listOf(current))).isFalse()
    }

    @Test
    fun `upgrade finish requires both migration outcomes for a Gradey account`() {
        assertThat(canFinishUpgrade(false, true, school = false, meals = false)).isFalse()
        assertThat(canFinishUpgrade(false, true, school = true, meals = false)).isFalse()
        assertThat(canFinishUpgrade(false, true, school = false, meals = true)).isFalse()
        assertThat(canFinishUpgrade(false, true, school = true, meals = true)).isTrue()
        assertThat(canFinishUpgrade(false, false, school = true, meals = true)).isFalse()
    }

    @Test
    fun `guest can finish upgrade unless work is active`() {
        assertThat(canFinishUpgrade(true, false, school = false, meals = false)).isTrue()
        assertThat(canFinishUpgrade(true, false, school = false, meals = false, working = true)).isFalse()
        assertThat(canFinishUpgrade(false, true, school = true, meals = true, working = true)).isFalse()
    }

    private fun progress(journey: OnboardingJourney, step: OnboardingStep) =
        OnboardingProgress(journey, step)

    private fun canFinishUpgrade(
        guest: Boolean,
        auth: Boolean,
        school: Boolean,
        meals: Boolean,
        working: Boolean = false,
    ) = canFinishUpgradeOnboarding(
        isGuestMode = guest,
        hasGradeySession = auth,
        hasRecordedSchoolMigration = school,
        hasRecordedMealsMigration = meals,
        isWorking = working,
    )

    private fun linkedAccount(
        id: String,
        provider: LinkedAccountProvider,
        status: LinkedAccountStatus = LinkedAccountStatus.ACTIVE,
    ) = LinkedSchoolAccount(
        id = id,
        provider = provider,
        displayName = id,
        status = status,
    )

    private fun reconcile(
        progress: OnboardingProgress,
        guest: Boolean,
        auth: Boolean,
        school: Boolean,
        cloudLinked: Boolean = true,
    ) = reconcileOnboardingProgress(progress, guest, auth, school, cloudLinked)
}
