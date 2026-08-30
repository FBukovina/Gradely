package com.bukovinafilip.gradey

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AppNavigationRestorationTest {
    @Test
    fun addSchoolRouteRestoresOnlyAboveAUsableSignedInSession() {
        assertThat(
            restoreSchoolRoute(
                isAddingSchool = true,
                reconnectAccountID = null,
                hasSchoolSession = true,
                availableLinkedAccountIDs = emptySet(),
            ),
        ).isEqualTo(RestoredSchoolRoute(RestoredSchoolDestination.ADD_SCHOOL))

        assertThat(
            restoreSchoolRoute(
                isAddingSchool = true,
                reconnectAccountID = null,
                hasSchoolSession = false,
                availableLinkedAccountIDs = emptySet(),
            ),
        ).isEqualTo(RestoredSchoolRoute(RestoredSchoolDestination.NONE))
    }

    @Test
    fun reconnectRouteRestoresByStableAccountID() {
        assertThat(
            restoreSchoolRoute(
                isAddingSchool = false,
                reconnectAccountID = " school-2 ",
                hasSchoolSession = true,
                availableLinkedAccountIDs = setOf("school-1", "school-2"),
            ),
        ).isEqualTo(
            RestoredSchoolRoute(
                destination = RestoredSchoolDestination.RECONNECT_SCHOOL,
                reconnectAccountID = "school-2",
            ),
        )
    }

    @Test
    fun reconnectRouteDoesNotRestoreWhenAccountDisappeared() {
        assertThat(
            restoreSchoolRoute(
                isAddingSchool = false,
                reconnectAccountID = "removed-school",
                hasSchoolSession = true,
                availableLinkedAccountIDs = setOf("school-1"),
            ),
        ).isEqualTo(RestoredSchoolRoute(RestoredSchoolDestination.NONE))
    }

    @Test
    fun reconnectRouteWinsOverCorruptSimultaneousAddFlag() {
        assertThat(
            restoreSchoolRoute(
                isAddingSchool = true,
                reconnectAccountID = "school-1",
                hasSchoolSession = true,
                availableLinkedAccountIDs = setOf("school-1"),
            ).destination,
        ).isEqualTo(RestoredSchoolDestination.RECONNECT_SCHOOL)
    }
}
