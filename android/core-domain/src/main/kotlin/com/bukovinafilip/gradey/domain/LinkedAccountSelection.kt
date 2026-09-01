package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount

fun selectRestorableSchoolAccount(
    accounts: List<LinkedSchoolAccount>,
    preferredAccountID: String?,
): LinkedSchoolAccount? {
    val activeSupportedSchools = accounts.filter {
        it.provider.isSupportedSchoolProvider && it.status == LinkedAccountStatus.ACTIVE
    }
    return preferredAccountID?.let { preferredID ->
        activeSupportedSchools.firstOrNull { it.id == preferredID }
    } ?: activeSupportedSchools.singleOrNull()
}

fun selectSchoolAccountRequiringReconnect(
    accounts: List<LinkedSchoolAccount>,
    preferredAccountID: String?,
): LinkedSchoolAccount? = preferredAccountID?.let { preferredID ->
    accounts.firstOrNull {
        it.id == preferredID &&
            it.provider.isSupportedSchoolProvider &&
            it.status == LinkedAccountStatus.ACTION_REQUIRED
    }
}
