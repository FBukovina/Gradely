package com.bukovinafilip.gradey

import android.content.Intent
import java.net.URI

internal const val FCM_DEEP_LINK_URL_EXTRA = "url"

internal enum class DeepLinkDestination {
    SUBJECTS,
    TIMETABLE,
}

internal data class DeepLinkRequest(
    val sequence: Long = 0,
    val rawUri: String? = null,
)

internal fun gradeyDeepLinkDestination(rawUri: String?): DeepLinkDestination? {
    val uri = rawUri
        ?.trim()
        ?.takeIf(String::isNotEmpty)
        ?.let { runCatching { URI(it) }.getOrNull() }
        ?: return null
    if (uri.scheme?.lowercase() !in setOf("gradey", "gradely")) return null

    val route = sequenceOf(uri.host, uri.path)
        .filterNotNull()
        .flatMap { value -> value.split('/').asSequence() }
        .map(String::trim)
        .firstOrNull(String::isNotEmpty)
        ?.lowercase()
        ?: return null

    return when (route) {
        "marks", "subjects" -> DeepLinkDestination.SUBJECTS
        "timetable" -> DeepLinkDestination.TIMETABLE
        else -> null
    }
}

internal fun canonicalGradeyDeepLink(rawUri: String?): String? =
    when (gradeyDeepLinkDestination(rawUri)) {
        DeepLinkDestination.SUBJECTS -> "gradey://marks"
        DeepLinkDestination.TIMETABLE -> "gradey://timetable"
        null -> null
    }

/**
 * Resolves the two launch channels used by Gradey.
 *
 * Explicit VIEW intent data owns the request whenever it is present. If that value is unsupported,
 * the request fails closed instead of mixing it with an unrelated extra. Background FCM
 * notification taps have no explicit data URI and deliver their data payload through the launcher
 * Activity extras, so only then is the backend's `url` extra considered. Both channels are reduced
 * to a recognized canonical destination before they cross into navigation state.
 */
internal fun resolveGradeyLaunchDeepLink(
    explicitIntentData: String?,
    notificationUrlExtra: String?,
): String? {
    val explicit = explicitIntentData?.trim()?.takeIf(String::isNotEmpty)
    return if (explicit != null) {
        canonicalGradeyDeepLink(explicit)
    } else {
        canonicalGradeyDeepLink(notificationUrlExtra)
    }
}

internal fun Intent?.resolvedGradeyLaunchDeepLink(): String? =
    resolveGradeyLaunchDeepLink(
        explicitIntentData = this?.dataString,
        notificationUrlExtra = this?.getStringExtra(FCM_DEEP_LINK_URL_EXTRA),
    )
