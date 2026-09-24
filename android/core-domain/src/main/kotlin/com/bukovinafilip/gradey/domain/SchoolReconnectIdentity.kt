package com.bukovinafilip.gradey.domain

/** Identity proof required before credentials may replace an existing linked school account. */
object SchoolReconnectIdentities {
    fun match(
        existingProviderUserID: String?,
        candidateProviderUserID: String?,
    ): Boolean {
        val existing = existingProviderUserID.canonicalProviderUserID() ?: return false
        val candidate = candidateProviderUserID.canonicalProviderUserID() ?: return false
        return existing == candidate
    }

    private fun String?.canonicalProviderUserID(): String? =
        this?.trim()?.takeIf(String::isNotEmpty)
}
