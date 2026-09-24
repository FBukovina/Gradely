package com.bukovinafilip.gradey.wear

import com.bukovinafilip.gradey.model.BakalariCredentials
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.TimetableWeek
import com.google.common.truth.Truth.assertThat
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneWearSyncPublisherTest {
    @Test
    fun restoredNoncurrentWeekUsesTheCachedCurrentWeekForStartupPublication() = runTest {
        val session = session("school-a.example", "student-a")
        var requestedCachedWeek: String? = null
        var published: GradeyWearSyncPayload? = null
        val cachedCurrentTimetable = loadCurrentWearTimetableCacheWhenNeeded(
            displayedTimetable = week("2026-09-07"),
            today = LocalDate.parse("2026-09-02"),
            loadCachedTimetable = { weekStart ->
                requestedCachedWeek = weekStart
                week("2026-08-31")
            },
        )

        val didPublish = publishCredentialFreeWearState(
            publicationSession = session,
            displayedTimetable = week("2026-09-07"),
            cachedCurrentTimetable = cachedCurrentTimetable,
            user = null,
            supportTier = GradeySupportTier.NONE,
            currentSession = { session },
            today = LocalDate.parse("2026-09-02"),
            publish = { payload, isStillCurrent ->
                if (!isStillCurrent()) {
                    false
                } else {
                    published = payload
                    true
                }
            },
        )

        assertThat(didPublish).isTrue()
        assertThat(requestedCachedWeek).isEqualTo("2026-08-31")
        val payload = checkNotNull(published)
        assertThat(payload.isSignedIn).isTrue()
        assertThat(payload.auth).isNull()
        assertThat(payload.timetable?.weekStart).isEqualTo("2026-08-31")
    }

    @Test
    fun signedInStateWithoutAnyCurrentTimetablePublishesAnAuthoritativeEmptyProjection() = runTest {
        val session = session("school-a.example", "student-a")
        var published: GradeyWearSyncPayload? = null

        val didPublish = publishCredentialFreeWearState(
            publicationSession = session,
            displayedTimetable = null,
            cachedCurrentTimetable = null,
            user = null,
            supportTier = GradeySupportTier.PLUS,
            currentSession = { session },
            today = LocalDate.parse("2026-09-02"),
            publish = { payload, isStillCurrent ->
                if (!isStillCurrent()) {
                    false
                } else {
                    published = payload
                    true
                }
            },
        )

        assertThat(didPublish).isTrue()
        val payload = checkNotNull(published)
        assertThat(payload.isSignedIn).isTrue()
        assertThat(payload.supportTier).isEqualTo(GradeySupportTier.PLUS)
        assertThat(payload.auth).isNull()
        assertThat(payload.timetable).isNull()
    }

    @Test
    fun queuedCachedProjectionCannotPublishAcrossASchoolAccountSwitch() = runTest {
        val sessionA = session("school-a.example", "student-a")
        val sessionB = session("school-b.example", "student-b")
        var currentSession: StoredSession? = sessionA
        var dataItemWritten = false

        val didPublish = publishCredentialFreeWearState(
            publicationSession = sessionA,
            displayedTimetable = week("2026-08-31"),
            cachedCurrentTimetable = null,
            user = null,
            supportTier = GradeySupportTier.NONE,
            currentSession = { currentSession },
            today = LocalDate.parse("2026-09-02"),
            publish = { _, isStillCurrent ->
                currentSession = sessionB
                if (!isStillCurrent()) {
                    false
                } else {
                    dataItemWritten = true
                    true
                }
            },
        )

        assertThat(didPublish).isFalse()
        assertThat(dataItemWritten).isFalse()
    }

    @Test
    fun signedOutProjectionContainsNoPrivateSchoolState() {
        val payload = GradeyWearSyncPayload.signedOut(nowEpochMillis = 200)

        assertThat(payload.isSignedIn).isFalse()
        assertThat(payload.auth).isNull()
        assertThat(payload.user).isNull()
        assertThat(payload.timetable).isNull()
    }

    @Test
    fun firstPublicationUsesRequestedWallClockGeneration() {
        assertThat(nextWearPayloadGeneration(previous = null, requested = 100)).isEqualTo(100)
    }

    @Test
    fun equalAndRolledBackClockStillAdvanceGeneration() {
        assertThat(nextWearPayloadGeneration(previous = 100, requested = 100)).isEqualTo(101)
        assertThat(nextWearPayloadGeneration(previous = 101, requested = 50)).isEqualTo(102)
    }

    @Test
    fun processRestartSeedAndOverflowRemainMonotonic() {
        assertThat(nextWearPayloadGeneration(previous = 500, requested = 300)).isEqualTo(501)
        assertThat(nextWearPayloadGeneration(previous = Long.MAX_VALUE, requested = 300))
            .isEqualTo(Long.MAX_VALUE)
    }

    @Test
    fun coordinatorKeepsTheWholePublishInGenerationOrder() = runTest {
        val coordinator = WearPublishCoordinator()
        val firstEntered = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val order = mutableListOf<String>()

        val first = async {
            coordinator.run {
                order += "first-start"
                firstEntered.complete(Unit)
                releaseFirst.await()
                order += "first-end"
            }
        }
        firstEntered.await()
        val second = async {
            coordinator.run { order += "second" }
        }

        runCurrent()
        assertThat(order).containsExactly("first-start").inOrder()

        releaseFirst.complete(Unit)
        first.await()
        second.await()

        assertThat(order).containsExactly("first-start", "first-end", "second").inOrder()
    }

    @Test
    fun coordinatorRejectsAQueuedSignedInPublishAfterSessionInvalidation() = runTest {
        val coordinator = WearPublishCoordinator()
        val signedOutStarted = CompletableDeferred<Unit>()
        val releaseSignedOut = CompletableDeferred<Unit>()
        var sessionIsCurrent = true
        var staleSignedInPublished = false

        val signedOut = async {
            coordinator.run {
                sessionIsCurrent = false
                signedOutStarted.complete(Unit)
                releaseSignedOut.await()
            }
        }
        signedOutStarted.await()
        val staleSignedIn = async {
            coordinator.runIf(
                isStillCurrent = { sessionIsCurrent },
                block = { staleSignedInPublished = true },
            )
        }

        runCurrent()
        releaseSignedOut.complete(Unit)
        signedOut.await()

        assertThat(staleSignedIn.await()).isFalse()
        assertThat(staleSignedInPublished).isFalse()
    }

    private fun session(host: String, username: String) = StoredSession(
        accessToken = "token-$username",
        refreshToken = "refresh-$username",
        tokenType = "Bearer",
        expiresAtEpochMillis = Long.MAX_VALUE,
        baseURL = "https://$host",
        bakalari = BakalariCredentials(username, "secret"),
    )

    private fun week(weekStart: String) = TimetableWeek(
        weekStart = weekStart,
        days = emptyList(),
        hours = emptyList(),
    )
}
