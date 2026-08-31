package com.bukovinafilip.gradey

import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.StoredSession
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class TimetablePublicationPolicyTest {
    @Test
    fun activeOwnerAcceptsTokenRotationWithinRequestedSchoolScope() {
        val requested = session("school-a.example", "student-a", "old-token")
        val refreshed = requested.copy(accessToken = "new-token")

        assertThat(activeSchoolSessionForScope(requested.cacheScope, refreshed)).isEqualTo(refreshed)
    }

    @Test
    fun accountSwitchAndSignOutRejectRequestedSchoolProjection() {
        val requested = session("school-a.example", "student-a", "token-a")
        val otherAccount = session("school-b.example", "student-b", "token-b")

        assertThat(activeSchoolSessionForScope(requested.cacheScope, otherAccount)).isNull()
        assertThat(activeSchoolSessionForScope(requested.cacheScope, null)).isNull()
    }

    @Test
    fun staleExpiryCannotRouteOverAReplacementSchoolSession() {
        val replacement = session("school-b.example", "student-b", "token-b")

        assertThat(shouldRouteToSchoolReconnect(replacement)).isFalse()
        assertThat(shouldRouteToSchoolReconnect(null)).isTrue()
    }

    @Test
    fun schoolMutationCanRestoreGateOnlyForItsInitiatingGradeyIdentity() {
        val cloudOwner = SchoolMutationOwner(gradeyAccountID = "gradey-a", isGuestMode = false)
        val guestOwner = SchoolMutationOwner(gradeyAccountID = null, isGuestMode = true)

        assertThat(cloudOwner.isCurrent("gradey-a", currentGuestMode = false)).isTrue()
        assertThat(cloudOwner.isCurrent("gradey-b", currentGuestMode = false)).isFalse()
        assertThat(cloudOwner.isCurrent(null, currentGuestMode = false)).isFalse()
        assertThat(guestOwner.isCurrent(null, currentGuestMode = true)).isTrue()
        assertThat(guestOwner.isCurrent(null, currentGuestMode = false)).isFalse()
    }

    private fun session(host: String, username: String, accessToken: String) = StoredSession(
        accessToken = accessToken,
        refreshToken = "refresh-$username",
        tokenType = "Bearer",
        expiresAtEpochMillis = Long.MAX_VALUE,
        baseURL = "https://$host",
        bakalari = BakalariCredentials(username, "secret"),
    )
}
