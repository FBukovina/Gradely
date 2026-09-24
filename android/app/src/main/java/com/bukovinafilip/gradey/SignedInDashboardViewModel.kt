package com.bukovinafilip.gradey

import androidx.lifecycle.ViewModel
import com.bukovinafilip.gradey.domain.SchoolSessionExpiredException
import com.bukovinafilip.gradey.domain.TodayPresentationState
import com.bukovinafilip.gradey.domain.TodayPresentationStates
import com.bukovinafilip.gradey.model.DashboardData
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class SignedInDashboardState(
    val scopeKey: String? = null,
    val dashboard: DashboardData? = null,
    val isLoading: Boolean = true,
    val failure: Throwable? = null,
    val sessionExpired: Boolean = false,
) {
    val presentationState: TodayPresentationState
        get() = TodayPresentationStates.resolve(
            hasDashboard = dashboard != null,
            hasSubjects = dashboard?.marksResponse?.subjects?.isNotEmpty() == true,
            isLoading = isLoading,
            hasError = failure != null,
        )
}

/**
 * Owns the cache-first dashboard state shared by Today and Subjects.
 *
 * Repository calls stay at the app composition boundary so this ViewModel remains narrowly scoped.
 * A monotonically increasing generation prevents a late response for one school from replacing the
 * next school's state.
 */
internal class SignedInDashboardViewModel : ViewModel() {
    private val mutableState = MutableStateFlow(SignedInDashboardState())
    val state: StateFlow<SignedInDashboardState> = mutableState.asStateFlow()

    private var generation = 0L

    val currentDashboard: DashboardData?
        get() = mutableState.value.dashboard

    fun switchScope(scopeKey: String?) {
        generation += 1
        mutableState.value = SignedInDashboardState(scopeKey = scopeKey)
    }

    fun adoptScope(scopeKey: String?) {
        generation += 1
        mutableState.value = mutableState.value.copy(
            scopeKey = scopeKey,
            isLoading = false,
        )
    }

    fun replaceDashboard(
        dashboard: DashboardData?,
        scopeKey: String? = mutableState.value.scopeKey,
        isLoading: Boolean = false,
    ) {
        generation += 1
        mutableState.value = mutableState.value.copy(
            scopeKey = scopeKey,
            dashboard = dashboard,
            isLoading = isLoading,
            failure = null,
            sessionExpired = false,
        )
    }

    fun clear(scopeKey: String? = null, isLoading: Boolean = false) {
        generation += 1
        mutableState.value = SignedInDashboardState(
            scopeKey = scopeKey,
            isLoading = isLoading,
        )
    }

    fun expireSession() {
        generation += 1
        mutableState.value = SignedInDashboardState(
            isLoading = false,
            sessionExpired = true,
        )
    }

    suspend fun loadCached(
        scopeKey: String?,
        load: suspend () -> DashboardData?,
    ) {
        val requestGeneration = beginRequest(scopeKey, clearOnScopeChange = true)
        val cached = try {
            load()
        } catch (error: CancellationException) {
            finishCancelledRequest(requestGeneration, scopeKey)
            throw error
        } catch (_: Throwable) {
            null
        }
        ensureCurrent(requestGeneration, scopeKey)
        mutableState.value = mutableState.value.copy(
            dashboard = cached ?: mutableState.value.dashboard,
            isLoading = true,
            failure = null,
            sessionExpired = false,
        )
    }

    suspend fun refresh(
        scopeKey: String?,
        forceRefresh: Boolean,
        load: suspend (Boolean) -> DashboardData,
    ): Throwable? {
        val requestGeneration = beginRequest(scopeKey, clearOnScopeChange = false)
        return try {
            val fresh = load(forceRefresh)
            ensureCurrent(requestGeneration, scopeKey)
            mutableState.value = mutableState.value.copy(
                dashboard = fresh,
                isLoading = false,
                failure = null,
                sessionExpired = false,
            )
            null
        } catch (error: CancellationException) {
            finishCancelledRequest(requestGeneration, scopeKey)
            throw error
        } catch (error: SchoolSessionExpiredException) {
            ensureCurrent(requestGeneration, scopeKey)
            mutableState.value = SignedInDashboardState(
                scopeKey = scopeKey,
                isLoading = false,
                sessionExpired = true,
            )
            error
        } catch (error: Throwable) {
            ensureCurrent(requestGeneration, scopeKey)
            mutableState.value = mutableState.value.copy(
                isLoading = false,
                failure = error,
                sessionExpired = false,
            )
            error
        }
    }

    suspend fun loadCacheFirst(
        scopeKey: String?,
        forceRefresh: Boolean = false,
        loadCached: suspend () -> DashboardData?,
        loadFresh: suspend (Boolean) -> DashboardData,
    ): Throwable? {
        this.loadCached(scopeKey, loadCached)
        return refresh(scopeKey, forceRefresh, loadFresh)
    }

    private fun beginRequest(scopeKey: String?, clearOnScopeChange: Boolean): Long {
        if (!clearOnScopeChange && mutableState.value.scopeKey != scopeKey) {
            throw CancellationException("The requested school is no longer active.")
        }
        generation += 1
        val previous = mutableState.value
        mutableState.value = if (clearOnScopeChange && previous.scopeKey != scopeKey) {
            SignedInDashboardState(scopeKey = scopeKey)
        } else {
            previous.copy(
                isLoading = true,
                failure = null,
                sessionExpired = false,
            )
        }
        return generation
    }

    private fun ensureCurrent(requestGeneration: Long, scopeKey: String?) {
        if (requestGeneration != generation || mutableState.value.scopeKey != scopeKey) {
            throw CancellationException("The active school changed while dashboard data was loading.")
        }
    }

    private fun finishCancelledRequest(requestGeneration: Long, scopeKey: String?) {
        if (requestGeneration == generation && mutableState.value.scopeKey == scopeKey) {
            mutableState.value = mutableState.value.copy(isLoading = false)
        }
    }
}
