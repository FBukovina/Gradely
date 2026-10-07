package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test

class GradeyAIEntryPolicyTest {
    @Test
    fun `entry policy requires both capabilities and an actual Gradey account`() {
        val cases = buildList {
            listOf(false, true).forEach { serviceConfigured ->
                listOf(false, true).forEach { cloudConfigured ->
                    listOf(false, true).forEach { hasAccount ->
                        listOf(false, true).forEach { guestMode ->
                            val expected = when {
                                !serviceConfigured || !cloudConfigured -> GradeyAIEntryState.NOT_CONFIGURED
                                guestMode || !hasAccount -> GradeyAIEntryState.SIGN_IN_REQUIRED
                                else -> GradeyAIEntryState.SERVICE
                            }
                            add(
                                Case(
                                    serviceConfigured = serviceConfigured,
                                    cloudConfigured = cloudConfigured,
                                    hasAccount = hasAccount,
                                    guestMode = guestMode,
                                    expected = expected,
                                ),
                            )
                        }
                    }
                }
            }
        }

        cases.forEach { case ->
            assertWithMessage(case.toString()).that(
                GradeyAIEntryPolicy.resolve(
                    isServiceConfigured = case.serviceConfigured,
                    isGradeyCloudConfigured = case.cloudConfigured,
                    hasGradeyAccount = case.hasAccount,
                    isGuestMode = case.guestMode,
                ),
            ).isEqualTo(case.expected)
        }
    }

    private data class Case(
        val serviceConfigured: Boolean,
        val cloudConfigured: Boolean,
        val hasAccount: Boolean,
        val guestMode: Boolean,
        val expected: GradeyAIEntryState,
    )
}
