package com.bukovinafilip.gradey.navigation

import com.bukovinafilip.gradey.DeepLinkDestination
import com.bukovinafilip.gradey.gradeyDeepLinkDestination

/**
 * Stable, argument-free destinations owned by the signed-in app shell.
 *
 * Feature-local detail state remains inside each destination. In particular, this graph does not
 * pass mutable domain objects or credentials through route strings.
 */
internal enum class MainDestination(
    val route: String,
    val isPrimary: Boolean,
) {
    TODAY(route = "main/today", isPrimary = true),
    SUBJECTS(route = "main/subjects", isPrimary = true),
    ABSENCE(route = "main/absence", isPrimary = true),
    TIMETABLE(route = "main/timetable", isPrimary = true),
    MEALS(route = "main/meals", isPrimary = true),
    ACCOUNT(route = "main/account", isPrimary = false),
    SUPPORT(route = "main/support", isPrimary = false),
    GRADEY_AI(route = "main/gradey-ai", isPrimary = false),
    ;

    companion object {
        val primaryDestinations: List<MainDestination> = listOf(
            TODAY,
            SUBJECTS,
            ABSENCE,
            TIMETABLE,
            MEALS,
        )

        fun fromRoute(route: String?): MainDestination? =
            entries.firstOrNull { it.route == route }
    }
}

internal fun DeepLinkDestination.toMainDestination(): MainDestination = when (this) {
    DeepLinkDestination.SUBJECTS -> MainDestination.SUBJECTS
    DeepLinkDestination.TIMETABLE -> MainDestination.TIMETABLE
}

/** Uses the existing strict Gradey/Gradely URI parser as the sole deep-link trust boundary. */
internal fun mainDestinationForDeepLink(rawUri: String?): MainDestination? =
    gradeyDeepLinkDestination(rawUri)?.toMainDestination()
