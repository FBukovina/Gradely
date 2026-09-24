package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test

class RetainedStravaCloudLinkTest {
    @Test
    fun `missing local session skips cloud linking`() = runTest {
        var linkCalls = 0

        val result = linkRetainedStravaSession(
            loadSession = { null },
            linkSession = { linkCalls += 1 },
        )

        assertThat(result).isEqualTo(RetainedStravaCloudLinkResult.NoLocalSession)
        assertThat(linkCalls).isEqualTo(0)
    }

    @Test
    fun `successful link forwards and returns the exact retained session`() = runTest {
        val retained = session()
        var linkedSession: StravaCZStoredSession? = null

        val result = linkRetainedStravaSession(
            loadSession = { retained },
            linkSession = { linkedSession = it },
        )

        assertThat(linkedSession).isSameInstanceAs(retained)
        assertThat(result).isInstanceOf(RetainedStravaCloudLinkResult.Linked::class.java)
        assertThat((result as RetainedStravaCloudLinkResult.Linked).session)
            .isSameInstanceAs(retained)
    }

    @Test
    fun `cloud failure reports the exact session without removing it locally`() = runTest {
        val retained = session()
        var storedSession: StravaCZStoredSession? = retained
        val cloudError = IllegalStateException("offline")

        val result = linkRetainedStravaSession(
            loadSession = { storedSession },
            linkSession = { throw cloudError },
        )

        assertThat(result).isInstanceOf(RetainedStravaCloudLinkResult.Failed::class.java)
        val failure = result as RetainedStravaCloudLinkResult.Failed
        assertThat(failure.session).isSameInstanceAs(retained)
        assertThat(failure.cause).isSameInstanceAs(cloudError)
        assertThat(storedSession).isSameInstanceAs(retained)
    }

    @Test(expected = CancellationException::class)
    fun `cloud link cancellation is rethrown`() = runTest {
        val retained = session()

        linkRetainedStravaSession(
            loadSession = { retained },
            linkSession = { throw CancellationException("cancelled") },
        )
    }

    private fun session() = StravaCZStoredSession(
        sessionID = "retained-session",
        serviceURL = "https://wss5.strava.cz/service",
        canteenNumber = "1234",
        username = "student",
        fullName = "Student Example",
        savedAtEpochMillis = 123L,
    )
}
