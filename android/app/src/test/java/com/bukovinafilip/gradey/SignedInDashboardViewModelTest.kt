package com.bukovinafilip.gradey

import com.bukovinafilip.gradey.domain.SchoolSessionExpiredException
import com.bukovinafilip.gradey.domain.TodayPresentationState
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.google.common.truth.Truth.assertThat
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Test

class SignedInDashboardViewModelTest {
    @Test
    fun `cached dashboard is visible while fresh content loads then fresh replaces it`() = runTest {
        val cached = dashboard("cached")
        val fresh = dashboard("fresh")
        val freshStarted = CompletableDeferred<Unit>()
        val releaseFresh = CompletableDeferred<Unit>()
        val viewModel = SignedInDashboardViewModel()

        val loading = async {
            viewModel.loadCacheFirst(
                scopeKey = "school-a",
                loadCached = { cached },
                loadFresh = {
                    freshStarted.complete(Unit)
                    releaseFresh.await()
                    fresh
                },
            )
        }
        freshStarted.await()

        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(cached)
        assertThat(viewModel.state.value.isLoading).isTrue()
        assertThat(viewModel.state.value.presentationState)
            .isEqualTo(TodayPresentationState.REFRESHING)

        releaseFresh.complete(Unit)
        assertThat(loading.await()).isNull()
        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(fresh)
        assertThat(viewModel.state.value.isLoading).isFalse()
        assertThat(viewModel.state.value.presentationState)
            .isEqualTo(TodayPresentationState.LOADED)
    }

    @Test
    fun `refresh failure retains exact cached dashboard as background error`() = runTest {
        val cached = dashboard("cached")
        val offline = IOException("offline")
        val viewModel = SignedInDashboardViewModel()

        val failure = viewModel.loadCacheFirst(
            scopeKey = "school-a",
            loadCached = { cached },
            loadFresh = { throw offline },
        )

        assertThat(failure).isSameInstanceAs(offline)
        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(cached)
        assertThat(viewModel.state.value.failure).isSameInstanceAs(offline)
        assertThat(viewModel.state.value.isLoading).isFalse()
        assertThat(viewModel.state.value.presentationState)
            .isEqualTo(TodayPresentationState.BACKGROUND_ERROR)
    }

    @Test
    fun `successful dashboard without subjects is empty rather than an error`() = runTest {
        val empty = DashboardData(MarksResponse())
        val viewModel = SignedInDashboardViewModel()

        val failure = viewModel.loadCacheFirst(
            scopeKey = "school-a",
            loadCached = { null },
            loadFresh = { empty },
        )

        assertThat(failure).isNull()
        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(empty)
        assertThat(viewModel.state.value.failure).isNull()
        assertThat(viewModel.state.value.presentationState)
            .isEqualTo(TodayPresentationState.EMPTY)
    }

    @Test
    fun `first load error becomes loaded after forced retry and clears error`() = runTest {
        val firstFailure = IOException("offline")
        val recovered = dashboard("recovered")
        val forceRefreshValues = mutableListOf<Boolean>()
        var attempt = 0
        val loadFresh: suspend (Boolean) -> DashboardData = { forceRefresh ->
            forceRefreshValues += forceRefresh
            if (attempt++ == 0) throw firstFailure
            recovered
        }
        val viewModel = SignedInDashboardViewModel()

        val failure = viewModel.loadCacheFirst(
            scopeKey = "school-a",
            loadCached = { null },
            loadFresh = loadFresh,
        )

        assertThat(failure).isSameInstanceAs(firstFailure)
        assertThat(viewModel.state.value.presentationState)
            .isEqualTo(TodayPresentationState.FIRST_LOAD_ERROR)

        assertThat(
            viewModel.refresh(
                scopeKey = "school-a",
                forceRefresh = true,
                load = loadFresh,
            ),
        ).isNull()
        assertThat(forceRefreshValues).containsExactly(false, true).inOrder()
        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(recovered)
        assertThat(viewModel.state.value.failure).isNull()
        assertThat(viewModel.state.value.presentationState)
            .isEqualTo(TodayPresentationState.LOADED)
    }

    @Test
    fun `expired session clears cached dashboard and requests reconnect`() = runTest {
        val expired = SchoolSessionExpiredException()
        val viewModel = SignedInDashboardViewModel()

        val failure = viewModel.loadCacheFirst(
            scopeKey = "school-a",
            loadCached = { dashboard("cached") },
            loadFresh = { throw expired },
        )

        assertThat(failure).isSameInstanceAs(expired)
        assertThat(viewModel.state.value.dashboard).isNull()
        assertThat(viewModel.state.value.failure).isNull()
        assertThat(viewModel.state.value.sessionExpired).isTrue()
        assertThat(viewModel.state.value.isLoading).isFalse()
    }

    @Test
    fun `account change clears old content before cache and ignores late old refresh`() = runTest {
        val oldCached = dashboard("school-a-cached")
        val oldFresh = dashboard("school-a-fresh")
        val newFresh = dashboard("school-b-fresh")
        val oldRefreshStarted = CompletableDeferred<Unit>()
        val releaseOldRefresh = CompletableDeferred<Unit>()
        val viewModel = SignedInDashboardViewModel()

        val oldRequest = async {
            viewModel.loadCacheFirst(
                scopeKey = "school-a",
                loadCached = { oldCached },
                loadFresh = {
                    oldRefreshStarted.complete(Unit)
                    releaseOldRefresh.await()
                    oldFresh
                },
            )
        }
        oldRefreshStarted.await()

        viewModel.loadCached(scopeKey = "school-b", load = { null })
        assertThat(viewModel.state.value.scopeKey).isEqualTo("school-b")
        assertThat(viewModel.state.value.dashboard).isNull()
        assertThat(viewModel.state.value.isLoading).isTrue()

        assertThat(
            viewModel.refresh(
                scopeKey = "school-b",
                forceRefresh = false,
                load = { newFresh },
            ),
        ).isNull()
        releaseOldRefresh.complete(Unit)

        assertThat(runCatching { oldRequest.await() }.exceptionOrNull())
            .isInstanceOf(CancellationException::class.java)
        assertThat(viewModel.state.value.scopeKey).isEqualTo("school-b")
        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(newFresh)
    }

    @Test
    fun `same student scope adoption retains content and invalidates an older refresh`() = runTest {
        val displayed = dashboard("displayed")
        val stale = dashboard("stale")
        val refreshStarted = CompletableDeferred<Unit>()
        val releaseRefresh = CompletableDeferred<Unit>()
        val viewModel = SignedInDashboardViewModel()
        viewModel.replaceDashboard(displayed, scopeKey = "local-school")

        val oldRequest = async {
            viewModel.refresh(
                scopeKey = "local-school",
                forceRefresh = false,
                load = {
                    refreshStarted.complete(Unit)
                    releaseRefresh.await()
                    stale
                },
            )
        }
        refreshStarted.await()

        viewModel.adoptScope("linked-school")
        releaseRefresh.complete(Unit)

        assertThat(runCatching { oldRequest.await() }.exceptionOrNull())
            .isInstanceOf(CancellationException::class.java)
        assertThat(viewModel.state.value.scopeKey).isEqualTo("linked-school")
        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(displayed)
        assertThat(viewModel.state.value.isLoading).isFalse()
    }

    @Test
    fun `stale fresh preload cannot reactivate an inactive school scope`() = runTest {
        val active = dashboard("active")
        var loadCalled = false
        val viewModel = SignedInDashboardViewModel()
        viewModel.replaceDashboard(active, scopeKey = "school-b")

        val failure = runCatching {
            viewModel.refresh(
                scopeKey = "school-a",
                forceRefresh = false,
                load = {
                    loadCalled = true
                    dashboard("stale")
                },
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(CancellationException::class.java)
        assertThat(loadCalled).isFalse()
        assertThat(viewModel.state.value.scopeKey).isEqualTo("school-b")
        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(active)
    }

    @Test
    fun `same scope missing cache keeps already displayed dashboard`() = runTest {
        val displayed = dashboard("displayed")
        val viewModel = SignedInDashboardViewModel()
        viewModel.replaceDashboard(displayed, scopeKey = "school-a")

        viewModel.loadCached(scopeKey = "school-a", load = { null })

        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(displayed)
        assertThat(viewModel.state.value.isLoading).isTrue()
    }

    @Test
    fun `cancellation propagates without losing retained dashboard or leaving loading stuck`() = runTest {
        val displayed = dashboard("displayed")
        val cancellation = CancellationException("cancelled")
        val viewModel = SignedInDashboardViewModel()
        viewModel.replaceDashboard(displayed, scopeKey = "school-a")

        val failure = runCatching {
            viewModel.refresh(
                scopeKey = "school-a",
                forceRefresh = true,
                load = { throw cancellation },
            )
        }.exceptionOrNull()

        assertThat(failure).isSameInstanceAs(cancellation)
        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(displayed)
        assertThat(viewModel.state.value.failure).isNull()
        assertThat(viewModel.state.value.isLoading).isFalse()
    }

    @Test
    fun `committed same scope replacement wins over an older slow refresh`() = runTest {
        val oldFresh = dashboard("old-fresh")
        val committed = dashboard("committed")
        val oldRefreshStarted = CompletableDeferred<Unit>()
        val releaseOldRefresh = CompletableDeferred<Unit>()
        val viewModel = SignedInDashboardViewModel()
        viewModel.replaceDashboard(dashboard("initial"), scopeKey = "school-a")

        val oldRequest = async {
            viewModel.refresh(
                scopeKey = "school-a",
                forceRefresh = false,
                load = {
                    oldRefreshStarted.complete(Unit)
                    releaseOldRefresh.await()
                    oldFresh
                },
            )
        }
        oldRefreshStarted.await()

        viewModel.replaceDashboard(committed, scopeKey = "school-a")
        releaseOldRefresh.complete(Unit)

        assertThat(runCatching { oldRequest.await() }.exceptionOrNull())
            .isInstanceOf(CancellationException::class.java)
        assertThat(viewModel.state.value.dashboard).isSameInstanceAs(committed)
        assertThat(viewModel.state.value.isLoading).isFalse()
    }

    private fun dashboard(id: String) = DashboardData(
        marksResponse = MarksResponse(
            subjects = listOf(
                Subject(
                    subjectInfo = SubjectInfo(
                        id = id,
                        abbrev = id,
                        name = id,
                    ),
                ),
            ),
        ),
    )
}
