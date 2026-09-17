package com.bukovinafilip.gradey.wear

import com.bukovinafilip.gradey.model.NextLessonWidgetChangeKind

internal const val WearComplicationCompactTokenMaxLength = 7

/** Labels that can be presented for a lesson without depending on Android resources. */
internal enum class WearLessonPresentationLabel {
    NOW,
    NEXT,
    CANCELED,
    SUBSTITUTION,
    ROOM_CHANGED,
    ADDED,
}

internal data class WearLessonChangePresentation(
    val label: WearLessonPresentationLabel?,
    val isCanceled: Boolean,
)

internal enum class WearComplicationPosition {
    CURRENT,
    NEXT,
}

internal enum class WearComplicationCompactTitleToken {
    NOW,
    NEXT,
    NOW_CANCELED,
    NOW_SUBSTITUTION,
    NOW_ROOM_CHANGED,
    NOW_ADDED,
    NEXT_CANCELED,
    NEXT_SUBSTITUTION,
    NEXT_ROOM_CHANGED,
    NEXT_ADDED,
}

internal enum class WearComplicationCompactBodyRole {
    BOUNDED_SUBJECT,
}

internal data class WearComplicationCompactFields(
    val titleToken: WearComplicationCompactTitleToken,
    val bodyRole: WearComplicationCompactBodyRole,
)

/**
 * A resource-independent complication policy. Compact surfaces keep temporal/change context in
 * the title and always reserve the body for a bounded subject token.
 */
internal data class WearComplicationLessonPresentation(
    val compactFields: WearComplicationCompactFields,
    val change: WearLessonChangePresentation,
) {
    val temporalLabel: WearLessonPresentationLabel
        get() = when (compactFields.titleToken) {
            WearComplicationCompactTitleToken.NOW,
            WearComplicationCompactTitleToken.NOW_CANCELED,
            WearComplicationCompactTitleToken.NOW_SUBSTITUTION,
            WearComplicationCompactTitleToken.NOW_ROOM_CHANGED,
            WearComplicationCompactTitleToken.NOW_ADDED,
            -> WearLessonPresentationLabel.NOW

            WearComplicationCompactTitleToken.NEXT,
            WearComplicationCompactTitleToken.NEXT_CANCELED,
            WearComplicationCompactTitleToken.NEXT_SUBSTITUTION,
            WearComplicationCompactTitleToken.NEXT_ROOM_CHANGED,
            WearComplicationCompactTitleToken.NEXT_ADDED,
            -> WearLessonPresentationLabel.NEXT
        }
}

internal fun String.toWearComplicationCompactToken(): String =
    take(WearComplicationCompactTokenMaxLength)

internal fun NextLessonWidgetChangeKind.toWearLessonChangePresentation(): WearLessonChangePresentation =
    when (this) {
        NextLessonWidgetChangeKind.NONE -> WearLessonChangePresentation(
            label = null,
            isCanceled = false,
        )

        NextLessonWidgetChangeKind.CANCELED -> WearLessonChangePresentation(
            label = WearLessonPresentationLabel.CANCELED,
            isCanceled = true,
        )

        NextLessonWidgetChangeKind.SUBSTITUTION -> WearLessonChangePresentation(
            label = WearLessonPresentationLabel.SUBSTITUTION,
            isCanceled = false,
        )

        NextLessonWidgetChangeKind.ROOM_CHANGED -> WearLessonChangePresentation(
            label = WearLessonPresentationLabel.ROOM_CHANGED,
            isCanceled = false,
        )

        NextLessonWidgetChangeKind.ADDED -> WearLessonChangePresentation(
            label = WearLessonPresentationLabel.ADDED,
            isCanceled = false,
        )
    }

internal fun wearComplicationLessonPresentation(
    position: WearComplicationPosition,
    changeKind: NextLessonWidgetChangeKind,
): WearComplicationLessonPresentation {
    val change = changeKind.toWearLessonChangePresentation()
    return WearComplicationLessonPresentation(
        compactFields = WearComplicationCompactFields(
            titleToken = when (position) {
                WearComplicationPosition.CURRENT -> when (changeKind) {
                    NextLessonWidgetChangeKind.NONE -> WearComplicationCompactTitleToken.NOW
                    NextLessonWidgetChangeKind.CANCELED -> WearComplicationCompactTitleToken.NOW_CANCELED
                    NextLessonWidgetChangeKind.SUBSTITUTION ->
                        WearComplicationCompactTitleToken.NOW_SUBSTITUTION

                    NextLessonWidgetChangeKind.ROOM_CHANGED ->
                        WearComplicationCompactTitleToken.NOW_ROOM_CHANGED

                    NextLessonWidgetChangeKind.ADDED -> WearComplicationCompactTitleToken.NOW_ADDED
                }

                WearComplicationPosition.NEXT -> when (changeKind) {
                    NextLessonWidgetChangeKind.NONE -> WearComplicationCompactTitleToken.NEXT
                    NextLessonWidgetChangeKind.CANCELED -> WearComplicationCompactTitleToken.NEXT_CANCELED
                    NextLessonWidgetChangeKind.SUBSTITUTION ->
                        WearComplicationCompactTitleToken.NEXT_SUBSTITUTION

                    NextLessonWidgetChangeKind.ROOM_CHANGED ->
                        WearComplicationCompactTitleToken.NEXT_ROOM_CHANGED

                    NextLessonWidgetChangeKind.ADDED -> WearComplicationCompactTitleToken.NEXT_ADDED
                }
            },
            bodyRole = WearComplicationCompactBodyRole.BOUNDED_SUBJECT,
        ),
        change = change,
    )
}
