package com.bukovinafilip.gradey

import java.net.URI

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
