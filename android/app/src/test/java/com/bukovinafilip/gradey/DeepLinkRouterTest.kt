package com.bukovinafilip.gradey

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class DeepLinkRouterTest {
    @Test
    fun `marks and subjects host and path variants open subjects`() {
        listOf(
            "gradey://marks",
            "gradely://subjects",
            "gradey:/marks",
            "gradey:///subjects",
            "GRADeY://MARKS?event=private",
        ).forEach { uri ->
            assertThat(gradeyDeepLinkDestination(uri)).isEqualTo(DeepLinkDestination.SUBJECTS)
        }
    }

    @Test
    fun `timetable host and path variants open timetable`() {
        listOf("gradey://timetable", "gradely:/timetable", "gradey:///timetable").forEach { uri ->
            assertThat(gradeyDeepLinkDestination(uri)).isEqualTo(DeepLinkDestination.TIMETABLE)
        }
    }

    @Test
    fun `untrusted and unknown links are ignored`() {
        listOf(null, "", "https://example.com/marks", "gradey://account", "not a uri").forEach { uri ->
            assertThat(gradeyDeepLinkDestination(uri)).isNull()
            assertThat(canonicalGradeyDeepLink(uri)).isNull()
        }
    }

    @Test
    fun `notification links are reduced to safe canonical destinations`() {
        assertThat(canonicalGradeyDeepLink("gradey://marks?event=secret"))
            .isEqualTo("gradey://marks")
        assertThat(canonicalGradeyDeepLink("gradely:///timetable?week=next"))
            .isEqualTo("gradey://timetable")
    }

    @Test
    fun `background notification extras resolve marks and timetable without retaining queries`() {
        assertThat(
            resolveGradeyLaunchDeepLink(
                explicitIntentData = null,
                notificationUrlExtra = "gradey://marks?event=private-event-id",
            ),
        ).isEqualTo("gradey://marks")
        assertThat(
            resolveGradeyLaunchDeepLink(
                explicitIntentData = null,
                notificationUrlExtra = "gradely:///timetable?week=next",
            ),
        ).isEqualTo("gradey://timetable")
    }

    @Test
    fun `valid explicit intent data takes precedence over a notification extra`() {
        assertThat(
            resolveGradeyLaunchDeepLink(
                explicitIntentData = "gradey://timetable?week=current",
                notificationUrlExtra = "gradey://marks?event=private-event-id",
            ),
        ).isEqualTo("gradey://timetable")
    }

    @Test
    fun `present but invalid explicit data fails closed instead of falling back to extras`() {
        listOf(
            "https://example.com/marks",
            "gradey://account",
            "javascript:gradey://marks",
            "not a uri",
        ).forEach { explicitData ->
            assertThat(
                resolveGradeyLaunchDeepLink(
                    explicitIntentData = explicitData,
                    notificationUrlExtra = "gradey://marks?event=private-event-id",
                ),
            ).isNull()
        }
    }

    @Test
    fun `absent explicit data accepts only recognized notification URLs`() {
        listOf(
            null,
            "",
            "https://example.com/marks",
            "gradey://account",
            "javascript:gradey://timetable",
            "not a uri",
        ).forEach { notificationUrl ->
            assertThat(
                resolveGradeyLaunchDeepLink(
                    explicitIntentData = null,
                    notificationUrlExtra = notificationUrl,
                ),
            ).isNull()
        }
    }
}
