package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class TodayLinkedAccountsTest {
    @Test
    fun `filters non school providers and resolves the active school`() {
        val first = account("first")
        val second = account("second")
        val canteen = account(
            "canteen",
            status = LinkedAccountStatus.FAILED,
            provider = LinkedAccountProvider.STRAVA_CZ,
        )

        val summary = TodayLinkedAccounts.resolve(listOf(first, canteen, second), "second")

        assertThat(summary.schoolAccounts.map { it.id }).containsExactly("first", "second").inOrder()
        assertThat(summary.activeAccount).isEqualTo(second)
        assertThat(summary.accountRequiringReconnect).isNull()
    }

    @Test
    fun `active account requiring action wins over another problem`() {
        val other = account("other", LinkedAccountStatus.ACTION_REQUIRED)
        val active = account("active", LinkedAccountStatus.FAILED)

        val summary = TodayLinkedAccounts.resolve(listOf(other, active), "active")

        assertThat(summary.accountRequiringReconnect).isEqualTo(active)
    }

    @Test
    fun `first supported problem is shown when active account is healthy`() {
        val healthy = account("healthy")
        val failed = account("failed", LinkedAccountStatus.FAILED)
        val action = account("action", LinkedAccountStatus.ACTION_REQUIRED)

        val summary = TodayLinkedAccounts.resolve(listOf(healthy, failed, action), "healthy")

        assertThat(summary.accountRequiringReconnect).isEqualTo(failed)
    }

    @Test
    fun `healthy schools do not produce a reconnect banner`() {
        val summary = TodayLinkedAccounts.resolve(listOf(account("healthy")), "healthy")

        assertThat(summary.accountRequiringReconnect).isNull()
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
