package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class LinkedAccountSelectionTest {
    @Test
    fun `preferred active Bakalari account wins when several schools exist`() {
        val first = account("first")
        val second = account("second")

        assertThat(selectRestorableSchoolAccount(listOf(first, second), "second"))
            .isEqualTo(second)
    }

    @Test
    fun `single active Bakalari account restores without a preference`() {
        val only = account("only")

        assertThat(selectRestorableSchoolAccount(listOf(only), null)).isEqualTo(only)
    }

    @Test
    fun `ambiguous action-required and unsupported accounts never auto-activate`() {
        val first = account("first")
        val second = account("second")
        val actionRequired = account("expired", status = LinkedAccountStatus.ACTION_REQUIRED)
        val legacyEduPage = account("edupage", provider = LinkedAccountProvider.EDU_PAGE)
        val canteen = account("canteen", provider = LinkedAccountProvider.STRAVA_CZ)

        assertThat(
            selectRestorableSchoolAccount(
                listOf(first, second, actionRequired, legacyEduPage, canteen),
                null,
            ),
        ).isNull()
        assertThat(selectRestorableSchoolAccount(listOf(actionRequired), "expired")).isNull()
        assertThat(selectRestorableSchoolAccount(listOf(legacyEduPage, canteen), null)).isNull()
        assertThat(
            selectSchoolAccountRequiringReconnect(
                listOf(first, actionRequired, legacyEduPage),
                "expired",
            ),
        ).isEqualTo(actionRequired)
        assertThat(selectSchoolAccountRequiringReconnect(listOf(actionRequired), null)).isNull()
        assertThat(selectSchoolAccountRequiringReconnect(listOf(legacyEduPage), "edupage")).isNull()
    }

    private fun account(
        id: String,
        status: LinkedAccountStatus = LinkedAccountStatus.ACTIVE,
        provider: LinkedAccountProvider = LinkedAccountProvider.BAKALARI,
    ) = LinkedSchoolAccount(
        id = id,
        provider = provider,
        displayName = id,
        status = status,
    )
}
