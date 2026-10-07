package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class CachedSchoolDirectoryTest {
    @Test
    fun `directory becomes stale at the seven day boundary`() {
        val cachedAt = 1_000L
        val directory = CachedSchoolDirectory(emptyList(), cachedAtEpochMillis = cachedAt)

        assertThat(
            directory.isStale(cachedAt + CachedSchoolDirectory.DEFAULT_MAX_AGE_MILLIS - 1),
        ).isFalse()
        assertThat(
            directory.isStale(cachedAt + CachedSchoolDirectory.DEFAULT_MAX_AGE_MILLIS),
        ).isTrue()
    }

    @Test
    fun `legacy cache format is not treated as current`() {
        val directory = CachedSchoolDirectory(
            schools = emptyList(),
            cachedAtEpochMillis = 1_000,
            formatVersion = null,
        )

        assertThat(directory.isCurrentFormat).isFalse()
    }
}
