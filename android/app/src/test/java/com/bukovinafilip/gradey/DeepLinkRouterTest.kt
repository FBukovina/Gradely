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
}
