package com.bukovinafilip.gradey.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.model.GradeyWearTimetableLesson
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.max

class WearMainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val store = (application as WearGradeyApplication).payloadStore
            val payload by store.payload.collectAsState()
            val scope = rememberCoroutineScope()
            var syncState by remember { mutableStateOf<WearSyncState>(WearSyncState.Idle) }

            suspend fun sync() {
                if (syncState == WearSyncState.Syncing) return
                syncState = WearSyncState.Syncing
                syncState = try {
                    when (refreshWearPayload(applicationContext, store)) {
                        WearRefreshResult.UPDATED -> WearSyncState.Updated
                        WearRefreshResult.NO_PHONE_PAYLOAD -> WearSyncState.NoPhonePayload
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    // Preserve the last valid phone payload and surface the failed manual refresh.
                    WearSyncState.Failed
                }
            }

            LaunchedEffect(Unit) { sync() }

            MaterialTheme {
                WearGradeyScreen(
                    payload = payload,
                    syncState = syncState,
                    onSync = { scope.launch { sync() } },
                )
            }
        }
    }
}

private sealed interface WearSyncState {
    data object Idle : WearSyncState
    data object Syncing : WearSyncState
    data object Updated : WearSyncState
    data object NoPhonePayload : WearSyncState
    data object Failed : WearSyncState
}

@Composable
private fun WearGradeyScreen(
    payload: GradeyWearSyncPayload?,
    syncState: WearSyncState,
    onSync: () -> Unit,
) {
    var nowEpochMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            nowEpochMillis = System.currentTimeMillis()
            delay(1_000)
        }
    }

    val signedInPayload = payload?.takeIf { it.isSignedIn }
    val page = WearTimeline.nowPage(signedInPayload?.timetable, nowEpochMillis)
    val remaining = WearTimeline.remainingLessonsToday(signedInPayload?.timetable, nowEpochMillis)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(WatchColors.background),
    ) {
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            item {
                Text(
                    text = stringResource(R.string.app_name),
                    color = WatchColors.primary,
                    fontWeight = FontWeight.ExtraBold,
                    style = MaterialTheme.typography.title2,
                )
            }

            signedInPayload?.user?.let { user ->
                item {
                    Text(
                        text = listOfNotNull(user.fullName, user.classAbbrev)
                            .filter(String::isNotBlank)
                            .joinToString(" · "),
                        modifier = Modifier.padding(horizontal = 12.dp),
                        color = Color.White.copy(alpha = 0.72f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.caption2,
                    )
                }
            }

            if (signedInPayload?.supportTier != null && signedInPayload.supportTier != GradeySupportTier.NONE) {
                item { SupporterBadge(signedInPayload.supportTier) }
            }

            item { SyncStatus(syncState) }

            when {
                payload == null -> item {
                    StatusCard(
                        title = stringResource(R.string.wear_no_timetable_title),
                        detail = stringResource(R.string.wear_no_timetable_detail),
                    )
                }

                !payload.isSignedIn -> item {
                    StatusCard(
                        title = stringResource(R.string.wear_signed_out_title),
                        detail = stringResource(R.string.wear_signed_out_detail),
                    )
                }

                else -> when (page) {
                    WearNowPage.NoTimetable -> item {
                        StatusCard(
                            title = stringResource(R.string.wear_no_timetable_title),
                            detail = stringResource(R.string.wear_no_timetable_detail),
                        )
                    }

                    WearNowPage.Stale -> item {
                        StatusCard(
                            title = stringResource(R.string.wear_stale_title),
                            detail = stringResource(R.string.wear_stale_detail),
                            accent = WatchColors.amber,
                        )
                    }

                    WearNowPage.DoneForToday -> item {
                        StatusCard(
                            title = stringResource(R.string.wear_done_title),
                            detail = stringResource(R.string.wear_done_detail),
                        )
                    }

                    is WearNowPage.InLesson -> item {
                        CurrentLessonHero(
                            lesson = page.lesson,
                            progress = page.progress,
                            status = if (page.lesson.isCanceled) {
                                stringResource(R.string.wear_status_canceled)
                            } else {
                                stringResource(R.string.wear_status_now)
                            },
                        )
                    }

                    is WearNowPage.BetweenLessons -> item {
                        CurrentLessonHero(
                            lesson = page.next,
                            progress = page.progress,
                            status = page.next.startEpochMillis?.let {
                                stringResource(R.string.wear_status_in, remainingText(it, nowEpochMillis))
                            } ?: stringResource(R.string.wear_status_up_next),
                            subtitlePrefix = stringResource(R.string.wear_break),
                        )
                    }
                }
            }

            if (signedInPayload?.timetable != null && page !is WearNowPage.Stale) {
                if (remaining.isEmpty()) {
                    item {
                        Text(
                            text = stringResource(R.string.wear_no_more_lessons),
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                            color = Color.White.copy(alpha = 0.58f),
                            textAlign = TextAlign.Center,
                            style = MaterialTheme.typography.caption2,
                        )
                    }
                } else {
                    item {
                        Text(
                            text = pluralStringResource(
                                R.plurals.wear_remaining_count,
                                remaining.size,
                                remaining.size,
                            ),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 20.dp, vertical = 5.dp),
                            color = Color.White.copy(alpha = 0.62f),
                            fontWeight = FontWeight.Bold,
                            style = MaterialTheme.typography.caption2,
                        )
                    }
                    items(remaining, key = { it.id }) { lesson ->
                        RemainingLessonRow(lesson)
                    }
                }
            }

            item {
                Button(
                    onClick = onSync,
                    enabled = syncState != WearSyncState.Syncing,
                    modifier = Modifier.padding(top = 6.dp),
                ) {
                    Text(
                        if (syncState == WearSyncState.Syncing) {
                            stringResource(R.string.wear_syncing)
                        } else {
                            stringResource(R.string.wear_sync)
                        },
                        maxLines = 1,
                    )
                }
            }

            item { Spacer(Modifier.height(8.dp)) }
        }
    }
}

@Composable
private fun SyncStatus(state: WearSyncState) {
    val text = when (state) {
        WearSyncState.Idle -> null
        WearSyncState.Syncing -> stringResource(R.string.wear_syncing_phone)
        WearSyncState.Updated -> stringResource(R.string.wear_sync_updated)
        WearSyncState.NoPhonePayload -> stringResource(R.string.wear_sync_no_payload)
        WearSyncState.Failed -> stringResource(R.string.wear_sync_failed)
    }
    if (text != null) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 2.dp),
            color = if (state == WearSyncState.Failed) WatchColors.canceled else Color.White.copy(alpha = 0.64f),
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.caption2,
        )
    }
}

@Composable
private fun StatusCard(title: String, detail: String, accent: Color = WatchColors.primary) {
    Column(
        modifier = Modifier
            .fillMaxWidth(0.86f)
            .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(18.dp))
            .padding(horizontal = 12.dp, vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(Modifier.size(7.dp).background(accent, CircleShape))
        Text(
            text = title,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.title3,
        )
        Text(
            text = detail,
            color = Color.White.copy(alpha = 0.62f),
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.caption2,
        )
    }
}

@Composable
private fun CurrentLessonHero(
    lesson: GradeyWearTimetableLesson,
    progress: Float,
    status: String,
    subtitlePrefix: String? = null,
) {
    val change = lesson.changeKind.toWearLessonChangePresentation()
    val changeLabel = change.label?.let { stringResource(it.stringResourceId()) }
    val canceled = change.isCanceled
    val accent = if (canceled) WatchColors.canceled else WatchColors.primary
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(modifier = Modifier.size(126.dp), contentAlignment = Alignment.Center) {
            LessonProgressArc(progress = progress, color = accent)
            Column(
                modifier = Modifier.padding(horizontal = 22.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = lesson.title ?: stringResource(R.string.wear_lesson_fallback),
                    color = Color.White,
                    fontWeight = FontWeight.ExtraBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.title1,
                    textDecoration = if (canceled) TextDecoration.LineThrough else TextDecoration.None,
                )
                Text(
                    text = status,
                    modifier = if (status == changeLabel) {
                        Modifier.clearAndSetSemantics { contentDescription = status }
                    } else {
                        Modifier
                    },
                    color = accent,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    style = MaterialTheme.typography.caption2,
                )
                if (changeLabel != null && status != changeLabel) {
                    LessonChangeLabel(
                        label = changeLabel,
                        color = changeColor(change),
                    )
                }
                val meta = buildList {
                    subtitlePrefix?.let(::add)
                    lesson.room?.takeIf(String::isNotBlank)?.let(::add)
                    lesson.teacher?.takeIf(String::isNotBlank)?.let(::add)
                }.joinToString(" · ")
                if (meta.isNotEmpty()) {
                    Text(
                        text = meta,
                        color = Color.White.copy(alpha = 0.60f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.caption2,
                    )
                }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            TimeEdge(
                value = timeText(lesson.startEpochMillis),
                label = stringResource(R.string.wear_start),
                alignEnd = false,
                canceled = canceled,
            )
            TimeEdge(
                value = timeText(lesson.endEpochMillis),
                label = stringResource(R.string.wear_end),
                alignEnd = true,
                canceled = canceled,
            )
        }
    }
}

@Composable
private fun LessonProgressArc(progress: Float, color: Color) {
    Canvas(Modifier.fillMaxSize()) {
        val stroke = 9.dp.toPx()
        val inset = stroke / 2
        val topLeft = Offset(inset, inset)
        val arcSize = androidx.compose.ui.geometry.Size(size.width - stroke, size.height - stroke)
        drawArc(
            color = Color.White.copy(alpha = 0.14f),
            startAngle = 133f,
            sweepAngle = 274f,
            useCenter = false,
            topLeft = topLeft,
            size = arcSize,
            style = Stroke(stroke, cap = StrokeCap.Round),
        )
        drawArc(
            brush = Brush.sweepGradient(listOf(WatchColors.primary, WatchColors.secondary, color)),
            startAngle = 133f,
            sweepAngle = 274f * progress.coerceIn(0f, 1f),
            useCenter = false,
            topLeft = topLeft,
            size = arcSize,
            style = Stroke(stroke, cap = StrokeCap.Round),
        )
    }
}

@Composable
private fun TimeEdge(value: String, label: String, alignEnd: Boolean, canceled: Boolean) {
    Column(horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start) {
        Text(
            text = value,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.title3,
            textDecoration = if (canceled) TextDecoration.LineThrough else TextDecoration.None,
        )
        Text(text = label, color = Color.White.copy(alpha = 0.55f), style = MaterialTheme.typography.caption2)
    }
}

@Composable
private fun RemainingLessonRow(lesson: GradeyWearTimetableLesson) {
    val change = lesson.changeKind.toWearLessonChangePresentation()
    val changeLabel = change.label?.let { stringResource(it.stringResourceId()) }
    Row(
        modifier = Modifier
            .fillMaxWidth(0.88f)
            .background(Color.White.copy(alpha = 0.07f), RoundedCornerShape(12.dp))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.size(5.dp).background(changeColor(change), CircleShape))
        Spacer(Modifier.width(7.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = lesson.detailTitle ?: stringResource(R.string.wear_lesson_fallback),
                color = Color.White,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.body2,
            )
            if (changeLabel != null) {
                LessonChangeLabel(
                    label = changeLabel,
                    color = changeColor(change),
                )
            }
            val meta = listOfNotNull(lesson.room, lesson.teacher)
                .filter(String::isNotBlank)
                .joinToString(" · ")
            if (meta.isNotEmpty()) {
                Text(
                    text = meta,
                    color = Color.White.copy(alpha = 0.55f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.caption2,
                )
            }
        }
        Spacer(Modifier.width(6.dp))
        Text(
            text = timeText(lesson.startEpochMillis),
            color = Color.White.copy(alpha = 0.68f),
            fontWeight = FontWeight.SemiBold,
            style = MaterialTheme.typography.caption1,
        )
    }
}

@Composable
private fun LessonChangeLabel(label: String, color: Color) {
    Text(
        text = label,
        modifier = Modifier.clearAndSetSemantics { contentDescription = label },
        color = color,
        fontWeight = FontWeight.Bold,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        style = MaterialTheme.typography.caption2,
    )
}

@Composable
private fun SupporterBadge(tier: GradeySupportTier) {
    val label = when (tier) {
        GradeySupportTier.PLUS -> stringResource(R.string.wear_support_plus)
        GradeySupportTier.STANDARD -> stringResource(R.string.wear_support_standard)
        GradeySupportTier.NONE -> return
    }
    Text(
        text = label,
        modifier = Modifier
            .background(WatchColors.primary.copy(alpha = 0.14f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 3.dp),
        color = WatchColors.primary,
        fontWeight = FontWeight.Bold,
        style = MaterialTheme.typography.caption2,
    )
}

private val GradeyWearTimetableLesson.isCanceled: Boolean
    get() = changeKind.toWearLessonChangePresentation().isCanceled

private fun timeText(epochMillis: Long?): String {
    if (epochMillis == null) return "--:--"
    return DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .format(Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()))
}

private fun remainingText(untilEpochMillis: Long, nowEpochMillis: Long): String {
    val seconds = max(0, ((untilEpochMillis - nowEpochMillis) / 1_000).toInt())
    val minutes = seconds / 60
    return when {
        minutes >= 60 -> "${minutes / 60} h ${minutes % 60} min"
        minutes < 1 -> "$seconds s"
        else -> "$minutes min"
    }
}

private fun changeColor(change: WearLessonChangePresentation): Color = when (change.label) {
    null -> WatchColors.primary
    WearLessonPresentationLabel.CANCELED -> WatchColors.canceled
    WearLessonPresentationLabel.SUBSTITUTION -> WatchColors.amber
    WearLessonPresentationLabel.ROOM_CHANGED -> WatchColors.teal
    WearLessonPresentationLabel.ADDED -> WatchColors.purple
    WearLessonPresentationLabel.NOW,
    WearLessonPresentationLabel.NEXT,
    -> WatchColors.primary
}

private object WatchColors {
    val primary = Color(0xFF1AFFBE)
    val secondary = Color(0xFF1FF98C)
    val background = Color(0xFF071C19)
    val canceled = Color(0xFFF24752)
    val amber = Color(0xFFD98F10)
    val teal = Color(0xFF108A94)
    val purple = Color(0xFFAF52DE)
}
