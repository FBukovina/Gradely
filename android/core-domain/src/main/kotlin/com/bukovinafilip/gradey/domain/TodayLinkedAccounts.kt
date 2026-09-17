package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount

data class TodayLinkedAccountSummary(
    val schoolAccounts: List<LinkedSchoolAccount>,
    val activeAccount: LinkedSchoolAccount?,
    val accountRequiringReconnect: LinkedSchoolAccount?,
)

object TodayLinkedAccounts {
    fun resolve(
        accounts: List<LinkedSchoolAccount>,
        activeAccountID: String?,
    ): TodayLinkedAccountSummary {
        val schools = accounts.filter { it.provider.isSupportedSchoolProvider }
        val active = schools.firstOrNull { it.id == activeAccountID }
        val reconnectCandidates = schools.filter {
            it.status == LinkedAccountStatus.ACTION_REQUIRED || it.status == LinkedAccountStatus.FAILED
        }
        return TodayLinkedAccountSummary(
            schoolAccounts = schools,
            activeAccount = active,
            accountRequiringReconnect = reconnectCandidates.firstOrNull { it.id == activeAccountID }
                ?: reconnectCandidates.firstOrNull(),
        )
    }
}
