package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test

class CacheFirstLoaderTest {
    @Test
    fun `cached content is shown before fresh content replaces it`() = runTest {
        val displayed = mutableListOf<String?>()

        val error = loadCacheFirst(
            loadCached = { "cached" },
            loadFresh = {
                assertThat(displayed).containsExactly("cached")
                "fresh"
            },
            onCached = displayed::add,
            onFresh = { displayed += it },
        )

        assertThat(error).isNull()
        assertThat(displayed).containsExactly("cached", "fresh").inOrder()
    }

    @Test
    fun `refresh failure leaves cached content displayed`() = runTest {
        val displayed = mutableListOf<String?>()
        val offline = java.io.IOException("offline")

        val error = loadCacheFirst(
            loadCached = { "cached" },
            loadFresh = { throw offline },
            onCached = displayed::add,
            onFresh = { displayed += it },
        )

        assertThat(error).isSameInstanceAs(offline)
        assertThat(displayed).containsExactly("cached")
    }

    @Test
    fun `missing or corrupt cache clears unrelated content before refresh`() = runTest {
        val missingDisplayed = mutableListOf<String?>()
        loadCacheFirst(
            loadCached = { null },
            loadFresh = { "fresh" },
            onCached = missingDisplayed::add,
            onFresh = { missingDisplayed += it },
        )

        val corruptDisplayed = mutableListOf<String?>()
        loadCacheFirst(
            loadCached = { error("corrupt") },
            loadFresh = { "recovered" },
            onCached = corruptDisplayed::add,
            onFresh = { corruptDisplayed += it },
        )

        assertThat(missingDisplayed).containsExactly(null, "fresh").inOrder()
        assertThat(corruptDisplayed).containsExactly(null, "recovered").inOrder()
    }

    @Test
    fun `cancellation is never converted into a refresh error`() = runTest {
        val failure = runCatching {
            loadCacheFirst(
                loadCached = { "cached" },
                loadFresh = { throw CancellationException("cancelled") },
                onCached = {},
                onFresh = {},
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(CancellationException::class.java)
    }
}
