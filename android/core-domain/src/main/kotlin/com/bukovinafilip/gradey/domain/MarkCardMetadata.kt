package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Mark

enum class MarkWeightBadgeKind {
    EXPLICIT,
    ESTIMATED,
}

data class MarkWeightBadge(
    val value: Double,
    val kind: MarkWeightBadgeKind,
)

data class MarkCardMetadata(
    val caption: String,
    val theme: String?,
    val typeLabel: String?,
    val weightBadge: MarkWeightBadge?,
    val pointsLabel: String?,
    val isNew: Boolean,
)

object MarkCardMetadataPolicy {
    fun resolve(
        mark: Mark,
        resolvedWeight: ResolvedMarkWeight,
        untitledCaption: String,
    ): MarkCardMetadata {
        val caption = mark.caption.trimmedOrNull()
        val theme = mark.theme.trimmedOrNull()
        val displayCaption = caption ?: theme ?: untitledCaption
        val displayedTheme = theme?.takeIf { caption != null && it != caption }
        val typeLabel = mark.typeNote.trimmedOrNull() ?: mark.type.trimmedOrNull()
        val weightBadge = when {
            mark.isPoints || resolvedWeight.value <= 1 -> null
            resolvedWeight.source == MarkWeightSource.EXPLICIT ->
                MarkWeightBadge(resolvedWeight.value, MarkWeightBadgeKind.EXPLICIT)
            resolvedWeight.source == MarkWeightSource.INFERRED ->
                MarkWeightBadge(resolvedWeight.value, MarkWeightBadgeKind.ESTIMATED)
            else -> null
        }
        val pointsLabel = if (mark.isPoints && mark.maxPoints != null) {
            "${mark.markText}/${mark.maxPoints}"
        } else {
            null
        }

        return MarkCardMetadata(
            caption = displayCaption,
            theme = displayedTheme,
            typeLabel = typeLabel,
            weightBadge = weightBadge,
            pointsLabel = pointsLabel,
            isNew = mark.isNew,
        )
    }

    private fun String?.trimmedOrNull(): String? = this?.trim()?.takeIf(String::isNotEmpty)
}
