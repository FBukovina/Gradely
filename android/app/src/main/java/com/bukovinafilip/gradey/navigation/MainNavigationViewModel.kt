package com.bukovinafilip.gradey.navigation

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import com.bukovinafilip.gradey.DeepLinkRequest
import kotlinx.coroutines.flow.StateFlow

/**
 * Persists only a one-shot navigation request that may arrive before the signed-in graph exists.
 *
 * The active back stack belongs exclusively to [androidx.navigation.NavController]. Keeping that
 * state out of this ViewModel avoids two competing navigation sources of truth.
 */
internal class MainNavigationViewModel(
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {
    val pendingDestinationRoute: StateFlow<String?> =
        savedStateHandle.getStateFlow(PENDING_DESTINATION_ROUTE_KEY, null)

    init {
        val restoredRoute = pendingDestinationRoute.value
        if (restoredRoute != null && MainDestination.fromRoute(restoredRoute) == null) {
            savedStateHandle[PENDING_DESTINATION_ROUTE_KEY] = null
        }
    }

    /**
     * Accepts only routes recognized by the existing strict deep-link parser.
     * Invalid input is ignored and never displaces an already pending valid request.
     */
    fun acceptDeepLink(rawUri: String?): Boolean {
        val destination = mainDestinationForDeepLink(rawUri) ?: return false
        requestDestination(destination)
        return true
    }

    fun acceptDeepLink(request: DeepLinkRequest): Boolean = acceptDeepLink(request.rawUri)

    fun requestDestination(destination: MainDestination) {
        savedStateHandle[PENDING_DESTINATION_ROUTE_KEY] = destination.route
    }

    /**
     * Conditionally consumes a request after navigation succeeds.
     *
     * Comparing the expected route prevents a delayed effect from clearing a newer request.
     */
    fun consumePendingDestination(route: String): Boolean {
        if (pendingDestinationRoute.value != route) return false
        savedStateHandle[PENDING_DESTINATION_ROUTE_KEY] = null
        return true
    }

    internal companion object {
        const val PENDING_DESTINATION_ROUTE_KEY = "main.pendingDestinationRoute"
    }
}
