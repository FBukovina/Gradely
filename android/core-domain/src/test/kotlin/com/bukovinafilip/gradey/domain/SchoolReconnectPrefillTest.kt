package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.StoredSession
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SchoolReconnectPrefillTest {
    @Test
    fun exactLinkedAccountReturnsOnlySafeFields() {
        val target = schoolAccount("school-a", schoolName = "Stored school")
        val session = session(linkedAccountID = target.id)

        val prefill = SchoolReconnectPrefills.resolve(session, target, listOf(target))

        assertThat(prefill).isEqualTo(
            SchoolReconnectPrefill(
                schoolURL = SchoolURL,
                schoolName = "Stored school",
                username = Username,
            ),
        )
        assertThat(prefill.toString()).doesNotContain(Password)
    }

    @Test
    fun schoolNameFallsBackFromAccountToSessionThenProvider() {
        val fromSession = SchoolReconnectPrefills.resolve(
            session = session(linkedAccountID = "school-a"),
            account = schoolAccount("school-a"),
            accounts = listOf(schoolAccount("school-a")),
        )
        val fromProvider = SchoolReconnectPrefills.resolve(
            session = session(linkedAccountID = "school-b", linkedSchoolName = ""),
            account = schoolAccount("school-b"),
            accounts = listOf(schoolAccount("school-b")),
        )

        assertThat(fromSession?.schoolName).isEqualTo("Session school")
        assertThat(fromProvider?.schoolName).isEqualTo(LinkedAccountProvider.BAKALARI.displayName)
    }

    @Test
    fun placeholderSchoolNamesFallBackToProviderWithoutReenteringTheForm() {
        val target = schoolAccount("school-a", schoolName = "Název školy")

        val prefill = SchoolReconnectPrefills.resolve(
            session = session(linkedAccountID = target.id, linkedSchoolName = " NÁZEV   ŠKOLY "),
            account = target,
            accounts = listOf(target),
        )

        assertThat(prefill?.schoolName).isEqualTo(LinkedAccountProvider.BAKALARI.displayName)
    }

    @Test
    fun unscopedSessionUsesOnlySupportedSchoolAndIgnoresMealAndUnsupportedAccounts() {
        val target = schoolAccount("school-a")
        val meal = LinkedSchoolAccount(
            id = "meal",
            provider = LinkedAccountProvider.STRAVA_CZ,
            displayName = "Canteen",
        )
        val unsupported = LinkedSchoolAccount(
            id = "future-school",
            provider = LinkedAccountProvider.EDU_PAGE,
            displayName = "Future school",
        )

        val prefill = SchoolReconnectPrefills.resolve(
            session = session(linkedAccountID = null),
            account = target,
            accounts = listOf(meal, unsupported, target),
        )

        assertThat(prefill?.schoolURL).isEqualTo(SchoolURL)
        assertThat(prefill?.username).isEqualTo(Username)
    }

    @Test
    fun unscopedSessionDoesNotGuessWhenTwoSupportedSchoolsExist() {
        val target = schoolAccount("school-a")

        val prefill = SchoolReconnectPrefills.resolve(
            session = session(linkedAccountID = null),
            account = target,
            accounts = listOf(target, schoolAccount("school-b")),
        )

        assertThat(prefill).isNull()
    }

    @Test
    fun sessionScopedToAnotherAccountIsNeverReused() {
        val target = schoolAccount("school-a")

        val prefill = SchoolReconnectPrefills.resolve(
            session = session(linkedAccountID = "school-b"),
            account = target,
            accounts = listOf(target),
        )

        assertThat(prefill).isNull()
    }

    @Test
    fun blankScopeIsNotTreatedAsAnUnscopedSession() {
        val target = schoolAccount("school-a")

        val prefill = SchoolReconnectPrefills.resolve(
            session = session(linkedAccountID = ""),
            account = target,
            accounts = listOf(target),
        )

        assertThat(prefill).isNull()
    }

    @Test
    fun unsupportedAccountIsNeverEligible() {
        val target = LinkedSchoolAccount(
            id = "future-school",
            provider = LinkedAccountProvider.EDU_PAGE,
            displayName = "Future school",
        )

        val prefill = SchoolReconnectPrefills.resolve(
            session = session(linkedAccountID = target.id),
            account = target,
            accounts = listOf(target),
        )

        assertThat(prefill).isNull()
    }

    private fun schoolAccount(id: String, schoolName: String? = null) = LinkedSchoolAccount(
        id = id,
        provider = LinkedAccountProvider.BAKALARI,
        displayName = "Student at School",
        schoolName = schoolName,
    )

    private fun session(
        linkedAccountID: String?,
        linkedSchoolName: String? = "Session school",
    ) = StoredSession(
        accessToken = "access",
        refreshToken = "refresh",
        tokenType = "Bearer",
        expiresAtEpochMillis = Long.MAX_VALUE,
        baseURL = SchoolURL,
        provider = SchoolProvider.BAKALARI,
        bakalari = BakalariCredentials(username = Username, password = Password),
        linkedAccountID = linkedAccountID,
        linkedAccountSchoolName = linkedSchoolName,
    )

    private companion object {
        const val SchoolURL = "https://school.example.cz"
        const val Username = "student"
        const val Password = "never-prefill-this"
    }
}
