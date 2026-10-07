package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.StoredSession

/** Non-secret values that may be carried into a school reconnect form. */
data class SchoolReconnectPrefill(
    val schoolURL: String,
    val schoolName: String,
    val username: String,
)

object SchoolReconnectPrefills {
    /**
     * Reuses a local session only when it is known to belong to [account]. An unscoped
     * session is safe to infer only when [account] is the sole supported school account.
     */
    fun resolve(
        session: StoredSession?,
        account: LinkedSchoolAccount,
        accounts: List<LinkedSchoolAccount>,
    ): SchoolReconnectPrefill? {
        session ?: return null
        if (!account.provider.isSupportedSchoolProvider) return null
        if (account.provider != LinkedAccountProvider.from(session.provider)) return null

        val supportedSchools = accounts.filter { it.provider.isSupportedSchoolProvider }
        if (supportedSchools.none { it.id == account.id }) return null

        val sessionAccountID = session.linkedAccountID
        val isExactAccount = sessionAccountID == account.id
        val isOnlySupportedSchool = sessionAccountID == null &&
            supportedSchools.singleOrNull()?.id == account.id
        if (!isExactAccount && !isOnlySupportedSchool) return null

        return SchoolReconnectPrefill(
            schoolURL = session.baseURL,
            schoolName = SchoolDirectoryNameResolver.displayableName(account.schoolName)
                ?: SchoolDirectoryNameResolver.displayableName(session.linkedAccountSchoolName)
                ?: account.provider.displayName,
            username = session.bakalari?.username.orEmpty(),
        )
    }
}
