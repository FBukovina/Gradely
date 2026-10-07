package com.bukovinafilip.gradey.wear

internal fun WearLessonPresentationLabel.stringResourceId(): Int = when (this) {
    WearLessonPresentationLabel.NOW -> R.string.wear_complication_now
    WearLessonPresentationLabel.NEXT -> R.string.wear_complication_next
    WearLessonPresentationLabel.CANCELED -> R.string.wear_status_canceled
    WearLessonPresentationLabel.SUBSTITUTION -> R.string.wear_status_substitution
    WearLessonPresentationLabel.ROOM_CHANGED -> R.string.wear_status_room_changed
    WearLessonPresentationLabel.ADDED -> R.string.wear_status_added
}

internal fun WearComplicationCompactTitleToken.stringResourceId(): Int = when (this) {
    WearComplicationCompactTitleToken.NOW -> R.string.wear_complication_now
    WearComplicationCompactTitleToken.NEXT -> R.string.wear_complication_next
    WearComplicationCompactTitleToken.NOW_CANCELED -> R.string.wear_compact_now_canceled
    WearComplicationCompactTitleToken.NOW_SUBSTITUTION -> R.string.wear_compact_now_substitution
    WearComplicationCompactTitleToken.NOW_ROOM_CHANGED -> R.string.wear_compact_now_room_changed
    WearComplicationCompactTitleToken.NOW_ADDED -> R.string.wear_compact_now_added
    WearComplicationCompactTitleToken.NEXT_CANCELED -> R.string.wear_compact_next_canceled
    WearComplicationCompactTitleToken.NEXT_SUBSTITUTION -> R.string.wear_compact_next_substitution
    WearComplicationCompactTitleToken.NEXT_ROOM_CHANGED -> R.string.wear_compact_next_room_changed
    WearComplicationCompactTitleToken.NEXT_ADDED -> R.string.wear_compact_next_added
}
