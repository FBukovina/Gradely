package com.bukovinafilip.gradey.navigation

import androidx.lifecycle.SavedStateHandle
import com.bukovinafilip.gradey.DeepLinkRequest
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class MainNavigationViewModelTest {
    @Test
    fun `deep link is deferred in saved state and survives ViewModel recreation`() {
        val firstHandle = SavedStateHandle()
        val first = MainNavigationViewModel(firstHandle)

        assertThat(first.acceptDeepLink("gradely:///subjects?event=private")).isTrue()
        assertThat(first.pendingDestinationRoute.value).isEqualTo(MainDestination.SUBJECTS.route)
        assertThat(firstHandle.get<String>(MainNavigationViewModel.PENDING_DESTINATION_ROUTE_KEY))
            .isEqualTo(MainDestination.SUBJECTS.route)

        val restored = MainNavigationViewModel(
            SavedStateHandle(
                mapOf(
                    MainNavigationViewModel.PENDING_DESTINATION_ROUTE_KEY to
                        first.pendingDestinationRoute.value,
                ),
            ),
        )
        assertThat(restored.pendingDestinationRoute.value).isEqualTo(MainDestination.SUBJECTS.route)
    }

    @Test
    fun `pending destination is consumed exactly once`() {
        val viewModel = MainNavigationViewModel(SavedStateHandle())
        viewModel.requestDestination(MainDestination.ACCOUNT)

        assertThat(viewModel.consumePendingDestination(MainDestination.ACCOUNT.route)).isTrue()
        assertThat(viewModel.pendingDestinationRoute.value).isNull()
        assertThat(viewModel.consumePendingDestination(MainDestination.ACCOUNT.route)).isFalse()
    }

    @Test
    fun `stale consumer cannot clear a newer request`() {
        val viewModel = MainNavigationViewModel(SavedStateHandle())
        viewModel.requestDestination(MainDestination.SUBJECTS)
        viewModel.requestDestination(MainDestination.TIMETABLE)

        assertThat(viewModel.consumePendingDestination(MainDestination.SUBJECTS.route)).isFalse()
        assertThat(viewModel.pendingDestinationRoute.value).isEqualTo(MainDestination.TIMETABLE.route)
        assertThat(viewModel.consumePendingDestination(MainDestination.TIMETABLE.route)).isTrue()
    }

    @Test
    fun `invalid deep link does not displace pending destination`() {
        val viewModel = MainNavigationViewModel(SavedStateHandle())
        viewModel.requestDestination(MainDestination.MEALS)

        assertThat(viewModel.acceptDeepLink("https://example.com/marks")).isFalse()
        assertThat(viewModel.acceptDeepLink(DeepLinkRequest(4, "gradey://account"))).isFalse()
        assertThat(viewModel.pendingDestinationRoute.value).isEqualTo(MainDestination.MEALS.route)
    }

    @Test
    fun `invalid restored route is discarded`() {
        val viewModel = MainNavigationViewModel(
            SavedStateHandle(
                mapOf(MainNavigationViewModel.PENDING_DESTINATION_ROUTE_KEY to "main/unknown"),
            ),
        )

        assertThat(viewModel.pendingDestinationRoute.value).isNull()
    }
}
