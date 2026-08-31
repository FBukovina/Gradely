package com.bukovinafilip.gradey.navigation

import com.bukovinafilip.gradey.DeepLinkDestination
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class MainDestinationTest {
    @Test
    fun `primary roots are stable complete and ordered`() {
        assertThat(MainDestination.primaryDestinations).containsExactly(
            MainDestination.TODAY,
            MainDestination.SUBJECTS,
            MainDestination.ABSENCE,
            MainDestination.TIMETABLE,
            MainDestination.MEALS,
        ).inOrder()
        assertThat(MainDestination.entries.filterNot(MainDestination::isPrimary)).containsExactly(
            MainDestination.ACCOUNT,
            MainDestination.SUPPORT,
            MainDestination.GRADEY_AI,
        ).inOrder()
        assertThat(MainDestination.entries.map(MainDestination::route).toSet())
            .hasSize(MainDestination.entries.size)
    }

    @Test
    fun `route lookup accepts only exact stable routes`() {
        MainDestination.entries.forEach { destination ->
            assertThat(MainDestination.fromRoute(destination.route)).isEqualTo(destination)
        }
        assertThat(MainDestination.fromRoute(null)).isNull()
        assertThat(MainDestination.fromRoute("")).isNull()
        assertThat(MainDestination.fromRoute("main/subjects/extra")).isNull()
        assertThat(MainDestination.fromRoute("MAIN/SUBJECTS")).isNull()
    }

    @Test
    fun `deep links use the existing strict parser and only map supported destinations`() {
        assertThat(DeepLinkDestination.SUBJECTS.toMainDestination())
            .isEqualTo(MainDestination.SUBJECTS)
        assertThat(DeepLinkDestination.TIMETABLE.toMainDestination())
            .isEqualTo(MainDestination.TIMETABLE)

        listOf("gradey://marks", "gradely:/subjects", "GRADeY:///MARKS?event=private")
            .forEach { uri ->
                assertThat(mainDestinationForDeepLink(uri)).isEqualTo(MainDestination.SUBJECTS)
            }
        listOf("gradey://timetable", "gradely:///timetable?week=next").forEach { uri ->
            assertThat(mainDestinationForDeepLink(uri)).isEqualTo(MainDestination.TIMETABLE)
        }
    }

    @Test
    fun `untrusted unknown and unsupported links have no main destination`() {
        listOf(
            null,
            "",
            "not a uri",
            "https://example.com/marks",
            "gradey://today",
            "gradey://absence",
            "gradey://meals",
            "gradey://account",
            "gradey://support",
        ).forEach { uri ->
            assertThat(mainDestinationForDeepLink(uri)).isNull()
        }
    }
}
