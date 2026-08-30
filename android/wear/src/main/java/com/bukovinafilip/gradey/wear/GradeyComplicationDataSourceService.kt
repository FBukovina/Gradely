package com.bukovinafilip.gradey.wear

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.model.GradeyWearTimetableLesson
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/** Current/next lesson complication backed by the exact payload persisted by the phone Data Layer. */
class GradeyComplicationDataSourceService : SuspendingComplicationDataSourceService() {
    override fun getPreviewData(type: ComplicationType): ComplicationData? = when (type) {
        ComplicationType.SHORT_TEXT -> shortText(
            title = getString(R.string.wear_complication_next),
            lessonTitle = getString(R.string.wear_complication_preview_abbreviation),
            contentDescription = getString(R.string.wear_complication_description),
        )

        ComplicationType.LONG_TEXT -> longText(
            text = getString(
                R.string.wear_complication_preview_long,
                getString(R.string.wear_complication_next),
            ),
            contentDescription = getString(R.string.wear_complication_description),
        )

        ComplicationType.RANGED_VALUE -> rangedValue(
            title = getString(R.string.wear_complication_preview_abbreviation),
            text = getString(R.string.wear_complication_now),
            progress = 0.5f,
            contentDescription = getString(R.string.wear_complication_description),
        )

        else -> null
    }

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData {
        val payload = (application as? WearGradeyApplication)?.payloadStore?.payload?.value
            ?: WearPayloadStore(applicationContext).payload.value
        return dataFor(request.complicationType, payload, System.currentTimeMillis())
    }

    private fun dataFor(
        type: ComplicationType,
        payload: GradeyWearSyncPayload?,
        nowEpochMillis: Long,
    ): ComplicationData {
        val nowNext = WearTimeline.nowAndNext(payload, nowEpochMillis)
        val lesson = nowNext.current ?: nowNext.next
        val status = if (nowNext.current != null) {
            getString(R.string.wear_complication_now)
        } else {
            getString(R.string.wear_complication_next)
        }
        val contentDescription = lesson?.let {
            listOf(status, it.detailTitle, it.timeRange, it.room)
                .filterNotNull()
                .filter(String::isNotBlank)
                .joinToString(", ")
        } ?: getString(R.string.wear_complication_no_lessons)

        return when (type) {
            ComplicationType.SHORT_TEXT -> shortText(
                title = if (lesson == null) null else status,
                lessonTitle = lesson?.title ?: getString(R.string.wear_complication_no_lessons),
                contentDescription = contentDescription,
            )

            ComplicationType.LONG_TEXT -> longText(
                text = lesson?.longText(status) ?: listOf(
                    getString(R.string.wear_complication_no_lessons),
                    getString(R.string.wear_complication_free_time),
                ).joinToString(" · "),
                contentDescription = contentDescription,
            )

            ComplicationType.RANGED_VALUE -> rangedValue(
                title = lesson?.title ?: "—",
                text = if (lesson == null) getString(R.string.wear_complication_no_lessons) else status,
                progress = lesson?.takeIf { nowNext.current != null }?.progress(nowEpochMillis) ?: 0f,
                contentDescription = contentDescription,
            )

            else -> shortText(
                title = null,
                lessonTitle = lesson?.title ?: getString(R.string.wear_complication_no_lessons),
                contentDescription = contentDescription,
            )
        }
    }

    private fun shortText(
        title: String?,
        lessonTitle: String,
        contentDescription: String,
    ): ShortTextComplicationData = ShortTextComplicationData.Builder(
        text = plain(lessonTitle),
        contentDescription = plain(contentDescription),
    )
        .apply { title?.let { setTitle(plain(it)) } }
        .setTapAction(openAppIntent())
        .build()

    private fun longText(text: String, contentDescription: String): LongTextComplicationData =
        LongTextComplicationData.Builder(
            text = plain(text),
            contentDescription = plain(contentDescription),
        )
            .setTapAction(openAppIntent())
            .build()

    private fun rangedValue(
        title: String,
        text: String,
        progress: Float,
        contentDescription: String,
    ): RangedValueComplicationData = RangedValueComplicationData.Builder(
        value = progress.coerceIn(0f, 1f),
        min = 0f,
        max = 1f,
        contentDescription = plain(contentDescription),
    )
        .setTitle(plain(title))
        .setText(plain(text))
        .setTapAction(openAppIntent())
        .build()

    private fun plain(value: String): ComplicationText = PlainComplicationText.Builder(value).build()

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, WearMainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun GradeyWearTimetableLesson.longText(status: String): String =
        listOf(status, detailTitle, timeRange ?: startEpochMillis?.let(::timeText), room)
            .filterNotNull()
            .filter(String::isNotBlank)
            .joinToString(" · ")

    private fun GradeyWearTimetableLesson.progress(nowEpochMillis: Long): Float {
        val start = startEpochMillis ?: return 0f
        val end = endEpochMillis ?: return 0f
        return WearTimeline.progress(start, end, nowEpochMillis)
    }

    private fun timeText(epochMillis: Long): String = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .format(Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()))
}
