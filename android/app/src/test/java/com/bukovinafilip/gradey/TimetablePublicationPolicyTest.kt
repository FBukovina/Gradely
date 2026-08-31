package com.bukovinafilip.gradey

import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.NotificationPreferences
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
    fun schoolMutationCanRestoreGateOnlyForItsExactIdentityAndOperation() {
        val cloudOwner = SchoolMutationOwner(
            gradeyAccountID = "gradey-a",
            isGuestMode = false,
            gradeyIdentityGeneration = 7L,
            operationToken = 41L,
        )
        val guestOwner = SchoolMutationOwner(
            gradeyAccountID = null,
            isGuestMode = true,
            gradeyIdentityGeneration = 7L,
            operationToken = 42L,
        )

        assertThat(cloudOwner.isCurrent("gradey-a", false, 7L, 41L)).isTrue()
        assertThat(cloudOwner.isCurrent("gradey-b", false, 7L, 41L)).isFalse()
        assertThat(cloudOwner.isCurrent("gradey-a", false, 8L, 41L)).isFalse()
        assertThat(cloudOwner.isCurrent("gradey-a", false, 7L, 43L)).isFalse()
        assertThat(cloudOwner.isCurrent("gradey-a", false, 7L, null)).isFalse()
        assertThat(guestOwner.isCurrent(null, true, 7L, 42L)).isTrue()
        assertThat(guestOwner.isCurrent(null, false, 7L, 42L)).isFalse()
    }

    @Test
    fun staleMutationCannotClearReplacementIdentityBusyState() {
        val heldA = SchoolMutationOwner("gradey-a", false, 7L, 41L)
        val replacementB = SchoolMutationOwner("gradey-b", false, 8L, 42L)

        assertThat(heldA.isCurrent("gradey-a", false, 8L, null)).isFalse()
        assertThat(heldA.isCurrent("gradey-b", false, 8L, 42L)).isFalse()
        assertThat(replacementB.isCurrent("gradey-b", false, 8L, 42L)).isTrue()
    }

    @Test
    fun linkedAccountRefreshPublishesOnlyToItsExactIdentityGeneration() {
        val owner = GradeyIdentityOwner(accountID = "gradey-a", generation = 7L)

        assertThat(owner.isCurrent("gradey-a", 7L, currentGuestMode = false)).isTrue()
        assertThat(owner.isCurrent(null, 8L, currentGuestMode = false)).isFalse()
        assertThat(owner.isCurrent("gradey-b", 8L, currentGuestMode = false)).isFalse()
        assertThat(owner.isCurrent("gradey-a", 8L, currentGuestMode = false)).isFalse()
        assertThat(owner.isCurrent("gradey-a", 7L, currentGuestMode = true)).isFalse()
    }

    @Test
    fun expiryClearsGlobalCloudProjectionSoOfflineReplacementCannotTrustAccountA() {
        val accountA = LinkedSchoolAccount(
            id = "linked-a",
            provider = LinkedAccountProvider.BAKALARI,
            displayName = "Student A",
            schoolName = "School A",
        )
        val retainedLocalSchool = session("school-a.example", "student-a", "school-token").copy(
            linkedAccountID = accountA.id,
        )
        val cleared = GradeyIdentityBoundaryState(
            linkedAccounts = listOf(accountA),
            activeLinkedAccountID = accountA.id,
            notificationPreferences = NotificationPreferences(newMarksEnabled = false),
        ).cleared()

        assertThat(cleared.linkedAccounts).isEmpty()
        assertThat(cleared.activeLinkedAccountID).isNull()
        assertThat(cleared.notificationPreferences).isEqualTo(NotificationPreferences.Default)
        assertThat(
            shouldTrustCachedSchoolAssociation(
                trustCachedAssociation = true,
                session = retainedLocalSchool,
                cachedAccounts = cleared.linkedAccounts,
            ),
        ).isFalse()
        assertThat(retainedLocalSchool.bakalari?.username).isEqualTo("student-a")
        assertThat(retainedLocalSchool.accessToken).isEqualTo("school-token")
    }

    @Test
    fun authoritativeReplacementSnapshotDetachesOnlyAnAbsentSchoolAssociation() {
        val retainedLocalSchool = session("school-a.example", "student-a", "school-token").copy(
            linkedAccountID = "linked-a",
        )
        val replacementSnapshot = listOf(
            LinkedSchoolAccount(
                id = "linked-b",
                provider = LinkedAccountProvider.BAKALARI,
                displayName = "Student B",
                schoolName = "School B",
            ),
        )
        val snapshotStillOwnsAssociation = replacementSnapshot +
            LinkedSchoolAccount(
                id = "linked-a",
                provider = LinkedAccountProvider.BAKALARI,
                displayName = "Student A",
                schoolName = "School A",
            )

        assertThat(
            shouldDetachSchoolAssociationAfterAuthoritativeRefresh(
                retainedLocalSchool,
                replacementSnapshot,
            ),
        ).isTrue()
        assertThat(
            shouldDetachSchoolAssociationAfterAuthoritativeRefresh(
                retainedLocalSchool,
                snapshotStillOwnsAssociation,
            ),
        ).isFalse()
        assertThat(
            shouldDetachSchoolAssociationAfterAuthoritativeRefresh(
                retainedLocalSchool,
                authoritativeAccounts = null,
            ),
        ).isFalse()
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
