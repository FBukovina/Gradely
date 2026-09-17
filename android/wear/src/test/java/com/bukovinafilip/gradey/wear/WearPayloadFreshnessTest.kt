package com.bukovinafilip.gradey.wear

import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class WearPayloadFreshnessTest {
    @Test
    fun newerSignedOutPayloadReplacesOlderSignedInPayload() {
        val signedIn = payload(generatedAtEpochMillis = 100, isSignedIn = true)
        val signedOut = payload(generatedAtEpochMillis = 200, isSignedIn = false)

        assertThat(selectFreshestWearPayload(signedIn, signedOut)).isSameInstanceAs(signedOut)
    }

    @Test
    fun olderSignedInPayloadCannotReplaceNewerSignedOutPayload() {
        val signedOut = payload(generatedAtEpochMillis = 200, isSignedIn = false)
        val signedIn = payload(generatedAtEpochMillis = 100, isSignedIn = true)

        assertThat(selectFreshestWearPayload(signedOut, signedIn)).isSameInstanceAs(signedOut)
    }

    @Test
    fun equalGenerationPrefersSignedOutRegardlessOfArrivalOrder() {
        val signedIn = payload(generatedAtEpochMillis = 200, isSignedIn = true)
        val signedOut = payload(generatedAtEpochMillis = 200, isSignedIn = false)

        assertThat(selectFreshestWearPayload(signedIn, signedOut)).isSameInstanceAs(signedOut)
        assertThat(selectFreshestWearPayload(signedOut, signedIn)).isSameInstanceAs(signedOut)
    }

    @Test
    fun newestPayloadWinsRegardlessOfDataItemArrivalOrder() {
        val oldest = payload(generatedAtEpochMillis = 100, isSignedIn = true)
        val middle = payload(generatedAtEpochMillis = 200, isSignedIn = true)
        val newest = payload(generatedAtEpochMillis = 300, isSignedIn = false)

        val forward = applyInOrder(oldest, middle, newest)
        val reverse = applyInOrder(newest, middle, oldest)
        val interleaved = applyInOrder(middle, oldest, newest)

        assertThat(forward).isSameInstanceAs(newest)
        assertThat(reverse).isSameInstanceAs(newest)
        assertThat(interleaved).isSameInstanceAs(newest)
    }

    @Test
    fun retainedNewerPayloadStillReportsPhoneDataAsUpToDate() {
        assertThat(wearRefreshResult(listOf(WearPayloadUpdateResult.RETAINED_NEWER)))
            .isEqualTo(WearRefreshResult.UPDATED)
        assertThat(wearRefreshResult(listOf(WearPayloadUpdateResult.INVALID)))
            .isEqualTo(WearRefreshResult.NO_PHONE_PAYLOAD)
        assertThat(wearRefreshResult(emptyList()))
            .isEqualTo(WearRefreshResult.NO_PHONE_PAYLOAD)
    }

    @Test
    fun deletionClearsOnlyThePayloadOwnedByThatSource() {
        assertThat(shouldClearWearPayloadForDeletedSource("phone-a", "phone-a")).isTrue()
        assertThat(shouldClearWearPayloadForDeletedSource("phone-a", "phone-b")).isFalse()
        assertThat(shouldClearWearPayloadForDeletedSource(null, "phone-a")).isTrue()
        assertThat(shouldClearWearPayloadForDeletedSource("phone-a", null)).isTrue()
    }

    @Test
    fun refreshRetainsOnlyPayloadsWhoseSourceStillExists() {
        assertThat(shouldRetainWearPayloadForSources("phone-a", setOf("phone-a", "phone-b"))).isTrue()
        assertThat(shouldRetainWearPayloadForSources("phone-a", setOf("phone-b"))).isFalse()
        assertThat(shouldRetainWearPayloadForSources("phone-a", emptySet())).isFalse()
        assertThat(shouldRetainWearPayloadForSources(null, setOf("phone-a"))).isFalse()
    }

    private fun applyInOrder(vararg payloads: GradeyWearSyncPayload): GradeyWearSyncPayload? =
        payloads.fold(null) { current, incoming -> selectFreshestWearPayload(current, incoming) }

    private fun payload(generatedAtEpochMillis: Long, isSignedIn: Boolean) = GradeyWearSyncPayload(
        generatedAtEpochMillis = generatedAtEpochMillis,
        isSignedIn = isSignedIn,
    )
}
