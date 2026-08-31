package com.bukovinafilip.gradey.feature.timetable

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.domain.TodayTimetableState
import com.bukovinafilip.gradey.domain.TodayTimetableSummaries
import com.bukovinafilip.gradey.domain.TodayTimetableSummary
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.ui.GradeyAuroraBackground
import com.bukovinafilip.gradey.ui.GradeyColors
import com.bukovinafilip.gradey.ui.GradeyIcons
import com.bukovinafilip.gradey.ui.StatusChip
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private val AccentTeal = GradeyColors.Primary
private val HeroStart = GradeyColors.Primary
private val HeroEnd = GradeyColors.Secondary
private val NoticeRed = GradeyColors.Poor
internal const val TIMETABLE_PREVIOUS_WEEK_TEST_TAG = "timetablePreviousWeek"
internal const val TIMETABLE_NEXT_WEEK_TEST_TAG = "timetableNextWeek"
internal const val TIMETABLE_TODAY_TEST_TAG = "timetableToday"

private data class TimetableDaySlot(
    val date: LocalDate,
    val day: ScheduledDay?,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimetableScreen(
    week: TimetableWeek?,
    isRefreshing: Boolean,
    errorMessage: String?,
    onRefresh: () -> Unit,
    onChangeWeek: (String) -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val locale = LocalConfiguration.current.locales[0]
    val monday = remember(week?.weekStart) { weekMonday(week) }
    val daySlots = remember(week, monday) { timetableDaySlots(week, monday) }
    val initialDate = daySlots.firstOrNull { it.day?.isToday == true }?.date
        ?: daySlots.firstOrNull { it.day?.isSchoolDay() == true }?.date
        ?: daySlots.firstOrNull()?.date
        ?: monday
    var selectedDate by rememberSaveable(week?.weekStart) { mutableStateOf(initialDate.toString()) }
    var selectedLesson by remember { mutableStateOf<ScheduledLesson?>(null) }
    val selectedDay = daySlots.firstOrNull { it.date.toString() == selectedDate }?.day
    val todaySummary = remember(week, selectedDay?.id) {
        week?.takeIf { selectedDay?.isToday == true }?.let(TodayTimetableSummaries::resolve)
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        GradeyAuroraBackground()
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(top = 28.dp),
        ) {
            TimetableHeader(
                isRefreshing = isRefreshing,
                onRefresh = onRefresh,
                onOpenAccount = onOpenAccount,
                onOpenGradeyTools = onOpenGradeyTools,
            )
            Spacer(Modifier.height(12.dp))
            WeekNavigator(
                monday = monday,
                locale = locale,
                enabled = !isRefreshing,
                onPrevious = { onChangeWeek(monday.minusWeeks(1).toString()) },
                onNext = { onChangeWeek(monday.plusWeeks(1).toString()) },
                onToday = { onChangeWeek(TimetableDates.todayString()) },
            )
            Spacer(Modifier.height(8.dp))
            DayStrip(
                daySlots = daySlots,
                selectedDate = selectedDate,
                locale = locale,
                onSelect = { selectedDate = it.toString() },
            )
            Spacer(Modifier.height(11.dp))
            HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
            if (!errorMessage.isNullOrBlank()) {
                Surface(
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .fillMaxWidth(),
                    shape = RoundedCornerShape(14.dp),
                    color = MaterialTheme.colorScheme.errorContainer,
                ) {
                    Text(
                        text = errorMessage,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        fontSize = 13.sp,
                        lineHeight = 17.sp,
                    )
                }
            }
            todaySummary?.let { summary ->
                TodaySummaryCard(summary)
            }
            LessonsList(
                day = selectedDay,
                isLoaded = week != null,
                onOpenLesson = { selectedLesson = it },
                modifier = Modifier.weight(1f),
            )
        }
    }

    selectedLesson?.let { lesson ->
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { selectedLesson = null },
            modifier = Modifier.padding(start = 8.dp, end = 8.dp, bottom = 8.dp),
            sheetState = sheetState,
            shape = RoundedCornerShape(48.dp),
            containerColor = Color.Transparent,
            contentColor = MaterialTheme.colorScheme.onSurface,
            tonalElevation = 12.dp,
            scrimColor = Color.Black.copy(alpha = 0.20f),
            dragHandle = null,
            contentWindowInsets = { WindowInsets(0, 0, 0, 0) },
        ) {
            LessonDetailSheet(lesson = lesson)
        }
    }
}

@Composable
private fun TodaySummaryCard(summary: TodayTimetableSummary) {
    if (summary.state == TodayTimetableState.UNAVAILABLE) return
    val currentName = summary.currentLesson?.localizedSubjectName()
    val nextLesson = summary.nextLesson
    val nextName = nextLesson?.localizedSubjectName()
    val title = when (summary.state) {
        TodayTimetableState.CURRENT -> stringResource(
            R.string.timetable_summary_now,
            currentName ?: stringResource(R.string.timetable_lesson_unknown),
        )
        TodayTimetableState.BEFORE_SCHOOL -> stringResource(R.string.timetable_summary_before)
        TodayTimetableState.BETWEEN_LESSONS -> stringResource(R.string.timetable_summary_between)
        TodayTimetableState.AFTER_SCHOOL -> stringResource(R.string.timetable_summary_after)
        TodayTimetableState.WEEKEND -> stringResource(R.string.timetable_weekend)
        TodayTimetableState.HOLIDAY -> stringResource(R.string.timetable_holiday)
        TodayTimetableState.EMPTY -> stringResource(R.string.timetable_summary_empty)
        TodayTimetableState.UNAVAILABLE -> return
    }
    val subtitle = when (summary.state) {
        TodayTimetableState.CURRENT -> summary.minutesRemainingInCurrent?.let {
            stringResource(R.string.timetable_summary_remaining, it)
        }
        TodayTimetableState.BEFORE_SCHOOL, TodayTimetableState.BETWEEN_LESSONS -> {
            val minutesUntilNext = summary.minutesUntilNext
            if (nextName != null && minutesUntilNext != null) {
                stringResource(R.string.timetable_summary_next_in, nextName, minutesUntilNext)
            } else {
                nextName?.let { stringResource(R.string.timetable_summary_next_is, it) }
            }
        }
        TodayTimetableState.AFTER_SCHOOL -> stringResource(
            if (summary.hasChanges) {
                R.string.timetable_summary_after_changes
            } else {
                R.string.timetable_summary_after_done
            },
        )
        TodayTimetableState.EMPTY -> stringResource(R.string.timetable_summary_empty_message)
        TodayTimetableState.WEEKEND, TodayTimetableState.HOLIDAY -> summary.dayDescription
        TodayTimetableState.UNAVAILABLE -> null
    }
    Surface(
        modifier = Modifier
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(
                title,
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
            )
            if (!subtitle.isNullOrBlank()) {
                Text(
                    subtitle,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 13.sp,
                    lineHeight = 17.sp,
                )
            }
            if (summary.currentLesson != null && nextLesson != null && nextName != null) {
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 5.dp),
                    thickness = 0.5.dp,
                    color = MaterialTheme.colorScheme.outlineVariant,
                )
                Text(
                    stringResource(R.string.timetable_summary_next, nextName) +
                        " · ${nextLesson.formattedTimeRange()}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 12.sp,
                    lineHeight = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            if (summary.hasChanges) {
                val count = summary.changedLessons.size
                val changeSummary = when {
                    count == 1 -> stringResource(
                        R.string.timetable_summary_changes_one,
                        summary.changedLessons.first().localizedSubjectName(),
                    )
                    count in 2..4 -> stringResource(R.string.timetable_summary_changes_few, count)
                    else -> stringResource(R.string.timetable_summary_changes_many, count)
                }
                Text(
                    changeSummary,
                    color = NoticeRed,
                    fontSize = 12.sp,
                    lineHeight = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun TimetableHeader(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
) {
    val openToolsDescription = stringResource(R.string.timetable_open_gradey_tools)
    val refreshDescription = stringResource(R.string.timetable_refresh)
    val openAccountDescription = stringResource(R.string.timetable_open_account)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(48.dp)
                .clip(CircleShape)
                .semantics { contentDescription = openToolsDescription }
                .clickable(role = Role.Button, onClick = onOpenGradeyTools),
            contentAlignment = Alignment.CenterStart,
        ) {
            Surface(
                modifier = Modifier.size(44.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shadowElevation = 2.dp,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Surface(
                        modifier = Modifier.size(30.dp),
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = GradeyIcons.Sparkles,
                                contentDescription = null,
                                tint = AccentTeal,
                                modifier = Modifier.size(22.dp),
                            )
                        }
                    }
                }
            }
        }

        Text(
            text = stringResource(R.string.timetable_title),
            color = MaterialTheme.colorScheme.onBackground,
            fontSize = 17.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.SemiBold,
        )

        Box(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .width(106.dp)
                .height(48.dp),
        ) {
            Surface(
                modifier = Modifier
                    .align(Alignment.Center)
                    .fillMaxWidth()
                    .height(44.dp),
                shape = RoundedCornerShape(22.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shadowElevation = 2.dp,
            ) {}
            Row(
                modifier = Modifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .semantics { contentDescription = refreshDescription }
                        .clickable(
                            enabled = !isRefreshing,
                            role = Role.Button,
                            onClick = onRefresh,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    if (isRefreshing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(21.dp),
                            color = AccentTeal,
                            strokeWidth = 2.5.dp,
                        )
                    } else {
                        Icon(
                            imageVector = GradeyIcons.Refresh,
                            contentDescription = null,
                            tint = AccentTeal,
                            modifier = Modifier.size(27.dp),
                        )
                    }
                }
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .semantics { contentDescription = openAccountDescription }
                        .clickable(role = Role.Button, onClick = onOpenAccount),
                    contentAlignment = Alignment.Center,
                ) {
                    Surface(
                        modifier = Modifier.size(36.dp),
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = GradeyIcons.User,
                                contentDescription = null,
                                tint = AccentTeal,
                                modifier = Modifier.size(22.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun WeekNavigator(
    monday: LocalDate,
    locale: Locale,
    enabled: Boolean,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onToday: () -> Unit,
) {
    val isCurrentWeek = monday == TimetableDates.monday(TimetableDates.today())
    val todayLabel = stringResource(R.string.timetable_today)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = if (isCurrentWeek) 48.dp else 52.dp)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        WeekArrow(
            description = stringResource(R.string.timetable_previous_week),
            enabled = enabled,
            onClick = onPrevious,
            modifier = Modifier.testTag(TIMETABLE_PREVIOUS_WEEK_TEST_TAG),
        ) {
            Icon(GradeyIcons.ArrowLeft, contentDescription = null, tint = AccentTeal, modifier = Modifier.size(24.dp))
        }
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = formatWeekRange(monday, locale),
                color = MaterialTheme.colorScheme.onBackground,
                fontSize = 18.sp,
                lineHeight = 22.sp,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
            )
            if (!isCurrentWeek) {
                Box(
                    modifier = Modifier
                        .sizeIn(minWidth = 48.dp, minHeight = 48.dp)
                        .testTag(TIMETABLE_TODAY_TEST_TAG)
                        .clip(RoundedCornerShape(24.dp))
                        .semantics { contentDescription = todayLabel }
                        .clickable(enabled = enabled, role = Role.Button, onClick = onToday),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = todayLabel,
                        modifier = Modifier.clearAndSetSemantics {},
                        color = AccentTeal,
                        fontSize = 12.sp,
                        lineHeight = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
        WeekArrow(
            description = stringResource(R.string.timetable_next_week),
            enabled = enabled,
            onClick = onNext,
            modifier = Modifier.testTag(TIMETABLE_NEXT_WEEK_TEST_TAG),
        ) {
            Icon(GradeyIcons.ArrowRight, contentDescription = null, tint = AccentTeal, modifier = Modifier.size(24.dp))
        }
    }
}

@Composable
private fun WeekArrow(
    description: String,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .size(48.dp)
            .clip(CircleShape)
            .semantics { contentDescription = description }
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier.size(40.dp),
            shape = CircleShape,
            color = MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 0.16f else 0.08f),
        ) {
            Box(contentAlignment = Alignment.Center) { icon() }
        }
    }
}

@Composable
private fun DayStrip(
    daySlots: List<TimetableDaySlot>,
    selectedDate: String,
    locale: Locale,
    onSelect: (LocalDate) -> Unit,
) {
    val weekdayFormatter = remember(locale) { DateTimeFormatter.ofPattern("EEE", locale) }
    val selectedLabel = stringResource(R.string.timetable_selected)
    val showDayTemplate = stringResource(R.string.timetable_show_day)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(66.dp)
            .horizontalScroll(rememberScrollState())
            .padding(start = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        daySlots.forEach { slot ->
            val selected = slot.date.toString() == selectedDate
            val description = "${slot.date.format(weekdayFormatter)}, ${slot.date.dayOfMonth}"
            val showDayLabel = String.format(locale, showDayTemplate, description)
            val shape = RoundedCornerShape(17.dp)
            val dayContentColor = if (selected) {
                GradeyColors.OnAccent
            } else {
                MaterialTheme.colorScheme.onSurface
            }
            Box(
                modifier = Modifier
                    .size(width = 52.dp, height = 66.dp)
                    .clip(shape)
                    .background(
                        if (selected) {
                            Brush.horizontalGradient(listOf(HeroStart, HeroEnd))
                        } else {
                            val surface = MaterialTheme.colorScheme.surfaceContainer
                            Brush.linearGradient(listOf(surface, surface))
                        },
                    )
                    .clickable(
                        role = Role.Tab,
                        onClickLabel = showDayLabel,
                        onClick = { onSelect(slot.date) },
                    )
                    .semantics {
                        contentDescription = "$description${if (selected) ", $selectedLabel" else ""}"
                        this.selected = selected
                    },
                contentAlignment = Alignment.TopCenter,
            ) {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Spacer(Modifier.height(9.dp))
                    Text(
                        text = slot.date.format(weekdayFormatter),
                        color = dayContentColor,
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = slot.date.dayOfMonth.toString(),
                        color = dayContentColor,
                        fontSize = 20.sp,
                        lineHeight = 24.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    val hasNotice = slot.day?.dayType.equals("notice", ignoreCase = true) ||
                        slot.day?.lessons?.any { it.changeKind != LessonChangeKind.NONE } == true
                    if (!selected && hasNotice) {
                        Spacer(Modifier.height(1.dp))
                        Box(Modifier.size(5.dp).background(NoticeRed, CircleShape))
                    }
                }
            }
        }
    }
}

@Composable
private fun LessonsList(
    day: ScheduledDay?,
    isLoaded: Boolean,
    onOpenLesson: (ScheduledLesson) -> Unit,
    modifier: Modifier = Modifier,
) {
    val lessons = day?.lessons.orEmpty()
    val dayType = day?.dayType.orEmpty().trim().lowercase(Locale.ROOT)
    val emptyTitle = when {
        !isLoaded -> stringResource(R.string.timetable_loading)
        dayType in setOf("holiday", "celebration", "directorday", "director day") ->
            stringResource(R.string.timetable_holiday)
        dayType == "weekend" -> stringResource(R.string.timetable_weekend)
        else -> stringResource(R.string.timetable_empty_title)
    }
    val emptyMessage = when {
        !isLoaded -> stringResource(R.string.timetable_unavailable)
        !day?.dayDescription.isNullOrBlank() -> day?.dayDescription.orEmpty()
        else -> stringResource(R.string.timetable_empty_message)
    }
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(top = 13.dp, end = 16.dp, bottom = 126.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (!isLoaded || lessons.isEmpty()) {
            item {
                Surface(
                    modifier = Modifier
                        .padding(start = 72.dp)
                        .fillMaxWidth()
                        .height(76.dp),
                    shape = RoundedCornerShape(20.dp),
                    color = MaterialTheme.colorScheme.surfaceContainer,
                    shadowElevation = 2.dp,
                ) {
                    Column(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            text = emptyTitle,
                            color = MaterialTheme.colorScheme.onSurface,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = emptyMessage,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 13.sp,
                            lineHeight = 17.sp,
                        )
                    }
                }
            }
        } else {
            items(lessons, key = ScheduledLesson::id) { lesson ->
                LessonRow(lesson = lesson, onClick = { onOpenLesson(lesson) })
            }
        }
    }
}

@Composable
private fun LessonRow(
    lesson: ScheduledLesson,
    onClick: () -> Unit,
) {
    val subjectName = lesson.localizedSubjectName()
    val detailDescription = stringResource(
        R.string.timetable_open_lesson_detail,
        subjectName,
        lesson.formattedTimeRange(),
    )
    val metadata = listOfNotNull(
        lesson.roomAbbrev ?: lesson.roomName,
        lesson.teacherName ?: lesson.teacherAbbrev,
        lesson.groups.takeIf(List<String>::isNotEmpty)?.joinToString(", "),
    )
    val hasExtras = !lesson.theme.isNullOrBlank() || lesson.hasHomework || lesson.changeKind != LessonChangeKind.NONE
    val rowHeight = if (hasExtras) 102.dp else 76.dp
    val isCanceled = lesson.changeKind == LessonChangeKind.CANCELED
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(rowHeight),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LessonTimeRail(lesson = lesson, modifier = Modifier.width(72.dp).fillMaxHeight())
        Surface(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight()
                .alpha(if (isCanceled) 0.68f else 1f)
                .semantics {
                    contentDescription = buildString {
                        append(detailDescription)
                        lesson.changeDescription?.takeIf { it.isNotBlank() }?.let { append(", $it") }
                    }
                },
            onClick = onClick,
            shape = RoundedCornerShape(20.dp),
            color = if (isCanceled) {
                MaterialTheme.colorScheme.errorContainer
            } else {
                MaterialTheme.colorScheme.surfaceContainer
            },
            shadowElevation = 1.dp,
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(46.dp)
                        .background(
                            MaterialTheme.colorScheme.primary.copy(alpha = 0.14f),
                            RoundedCornerShape(12.dp),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = lesson.subjectAbbrev ?: subjectName.take(2),
                        color = AccentTeal,
                        fontSize = 17.sp,
                        lineHeight = 21.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Spacer(Modifier.width(12.dp))
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        text = subjectName,
                        color = MaterialTheme.colorScheme.onSurface,
                        fontSize = 18.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textDecoration = if (isCanceled) TextDecoration.LineThrough else TextDecoration.None,
                    )
                    if (metadata.isNotEmpty()) {
                        Text(
                            text = metadata.joinToString(" · "),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 14.sp,
                            lineHeight = 17.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    lesson.theme?.takeIf { it.isNotBlank() }?.let { topic ->
                        Text(
                            text = topic,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 13.sp,
                            lineHeight = 17.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    if (lesson.changeKind != LessonChangeKind.NONE || lesson.hasHomework) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            if (lesson.changeKind != LessonChangeKind.NONE) {
                                StatusChip(
                                    text = lesson.localizedChangeLabel(),
                                    color = lesson.changeKind.color(),
                                )
                            }
                            if (lesson.hasHomework) {
                                StatusChip(
                                    text = stringResource(R.string.timetable_detail_homework),
                                    color = AccentTeal,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LessonTimeRail(
    lesson: ScheduledLesson,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(top = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = lesson.hour.caption,
            color = MaterialTheme.colorScheme.onBackground,
            fontSize = 18.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = lesson.hour.beginTime.clockDisplay(),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
            lineHeight = 16.sp,
            fontWeight = FontWeight.Medium,
        )
        Text(
            text = lesson.hour.endTime.clockDisplay(),
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.72f),
            fontSize = 13.sp,
            lineHeight = 16.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun LessonDetailSheet(lesson: ScheduledLesson) {
    val subjectName = lesson.localizedSubjectName()
    val teacher = lesson.teacherName ?: lesson.teacherAbbrev
    val room = lesson.roomName ?: lesson.roomAbbrev
    val hasTopic = !lesson.theme.isNullOrBlank()
    val changeDetails = listOfNotNull(
        lesson.change?.changeSubject?.takeIf(String::isNotBlank)?.let { R.string.timetable_change_subject to it },
        lesson.change?.day?.takeIf(String::isNotBlank)?.let { R.string.timetable_change_day to it },
        lesson.change?.hours?.takeIf(String::isNotBlank)?.let { R.string.timetable_change_hours to it },
        lesson.change?.time?.takeIf(String::isNotBlank)?.let { R.string.timetable_change_time to it },
        (lesson.change?.typeName ?: lesson.change?.typeAbbrev)
            ?.takeIf(String::isNotBlank)
            ?.let { R.string.timetable_change_type to it },
    )
    val detailRowCount = listOfNotNull(teacher, room).size +
        (if (lesson.groups.isNotEmpty()) 1 else 0) +
        (if (hasTopic) 1 else 0) +
        (if (lesson.hasHomework) 1 else 0) +
        (if (!lesson.changeDescription.isNullOrBlank()) 1 else 0) +
        changeDetails.size
    val sheetHeight = (250 + detailRowCount * 45).coerceIn(390, 700).dp
    val background = MaterialTheme.colorScheme.background
    val surface = MaterialTheme.colorScheme.surfaceContainer
    val surfaceHigh = MaterialTheme.colorScheme.surfaceContainerHigh
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(sheetHeight)
            .clip(RoundedCornerShape(48.dp))
            .background(
                Brush.verticalGradient(
                    colorStops = arrayOf(
                        0f to surfaceHigh,
                        0.34f to surface,
                        1f to background,
                    ),
                ),
            ),
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(GradeyColors.Primary.copy(alpha = 0.28f), Color.Transparent),
                    center = Offset(size.width * 0.76f, size.height * 0.05f),
                    radius = size.width * 0.65f,
                ),
                radius = size.width * 0.65f,
                center = Offset(size.width * 0.76f, size.height * 0.05f),
            )
        }
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(6.dp))
            Box(
                modifier = Modifier
                    .size(width = 34.dp, height = 5.dp)
                    .background(MaterialTheme.colorScheme.outline, RoundedCornerShape(3.dp)),
            )
            Spacer(Modifier.height(16.dp))
            Text(
                text = subjectName,
                color = MaterialTheme.colorScheme.onBackground,
                fontSize = 20.sp,
                lineHeight = 26.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(31.dp))
            Box(
                modifier = Modifier
                    .padding(horizontal = 15.dp)
                    .fillMaxWidth()
                    .height(96.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Brush.horizontalGradient(listOf(HeroStart, HeroEnd)))
                    .semantics {
                        contentDescription = "$subjectName, ${lesson.formattedTimeRange()}"
                    },
                contentAlignment = Alignment.CenterStart,
            ) {
                Column(modifier = Modifier.padding(horizontal = 24.dp)) {
                    Text(
                        text = lesson.formattedTimeRange(),
                        color = Color(0xFFE2F7F1),
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Spacer(Modifier.height(5.dp))
                    Text(
                        text = subjectName,
                        color = Color.White,
                        fontSize = 22.sp,
                        lineHeight = 28.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
            Spacer(Modifier.height(15.dp))
            Surface(
                modifier = Modifier
                    .padding(horizontal = 15.dp)
                    .fillMaxWidth()
                    .height((18 + detailRowCount * 45).dp),
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surfaceContainer,
                shadowElevation = 1.dp,
            ) {
                Column(
                    modifier = Modifier.padding(start = 20.dp, top = 13.dp, end = 20.dp, bottom = 11.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    teacher?.let {
                        DetailRow(
                            icon = { Icon(GradeyIcons.User, contentDescription = null) },
                            label = stringResource(R.string.timetable_detail_teacher),
                            value = it,
                        )
                    }
                    room?.let {
                        DetailRow(
                            icon = { Icon(GradeyIcons.MeetingRoom, contentDescription = null) },
                            label = stringResource(R.string.timetable_detail_room),
                            value = it,
                        )
                    }
                    if (lesson.groups.isNotEmpty()) {
                        DetailRow(
                            icon = { Icon(GradeyIcons.User, contentDescription = null) },
                            label = stringResource(R.string.timetable_detail_group),
                            value = lesson.groups.joinToString(", "),
                        )
                    }
                    lesson.theme?.takeIf { it.isNotBlank() }?.let { topic ->
                        DetailRow(
                            icon = { Icon(GradeyIcons.Book, contentDescription = null) },
                            label = stringResource(R.string.timetable_detail_topic),
                            value = topic,
                        )
                    }
                    if (lesson.hasHomework) {
                        DetailRow(
                            icon = { Icon(GradeyIcons.Book, contentDescription = null) },
                            label = stringResource(R.string.timetable_detail_homework),
                            value = stringResource(R.string.timetable_detail_homework_assigned),
                        )
                    }
                    lesson.changeDescription?.takeIf { it.isNotBlank() }?.let { change ->
                        DetailRow(
                            icon = { Icon(GradeyIcons.Information, contentDescription = null) },
                            label = lesson.localizedChangeLabel(),
                            value = change,
                        )
                    }
                    changeDetails.forEach { (label, value) ->
                        DetailRow(
                            icon = { Icon(GradeyIcons.Information, contentDescription = null) },
                            label = stringResource(label),
                            value = value,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailRow(
    icon: @Composable () -> Unit,
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(38.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier
                .width(28.dp)
                .padding(top = 2.dp),
            contentAlignment = Alignment.TopStart,
        ) {
            Box(
                modifier = Modifier
                    .size(18.dp)
                    .semantics { contentDescription = label },
            ) {
                CompositionLocalProvider(LocalContentColor provides AccentTeal) { icon() }
            }
        }
        Column {
            Text(
                text = label,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = value,
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 17.sp,
                lineHeight = 20.sp,
                fontWeight = FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

private fun timetableDaySlots(week: TimetableWeek?, monday: LocalDate): List<TimetableDaySlot> {
    val days = week?.days.orEmpty()
    if (days.isEmpty()) {
        return (0L..4L).map { offset -> TimetableDaySlot(monday.plusDays(offset), null) }
    }
    return days.mapIndexed { index, day ->
        val parsed = TimetableDates.parseApiDate(day.date)
        val fallbackOffset = when (day.dayOfWeek) {
            in 1..7 -> day.dayOfWeek - 1L
            else -> index.toLong().coerceIn(0L, 6L)
        }
        TimetableDaySlot(parsed ?: monday.plusDays(fallbackOffset), day)
    }
        .distinctBy(TimetableDaySlot::date)
        .sortedBy(TimetableDaySlot::date)
}

private fun weekMonday(week: TimetableWeek?): LocalDate {
    val parsed = week?.weekStart?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
    return TimetableDates.monday(parsed ?: TimetableDates.today())
}

private fun ScheduledDay.isSchoolDay(): Boolean = when (dayType.trim().lowercase(Locale.ROOT)) {
    "holiday", "celebration", "directorday", "director day", "weekend" -> false
    else -> true
}

internal fun formatWeekRange(monday: LocalDate, locale: Locale): String {
    val friday = monday.plusDays(4)
    val monthFormatter = DateTimeFormatter.ofPattern("MMM", locale)
    return if (monday.month == friday.month) {
        "${monday.dayOfMonth}–${friday.dayOfMonth} ${monday.format(monthFormatter)}"
    } else {
        "${monday.dayOfMonth} ${monday.format(monthFormatter)} – ${friday.dayOfMonth} ${friday.format(monthFormatter)}"
    }
}

@Composable
private fun ScheduledLesson.localizedSubjectName(): String =
    subjectName ?: subjectAbbrev ?: stringResource(R.string.timetable_lesson_unknown)

@Composable
private fun ScheduledLesson.localizedChangeLabel(): String = when (changeKind) {
    LessonChangeKind.NONE -> stringResource(R.string.timetable_detail_change)
    LessonChangeKind.CANCELED -> stringResource(R.string.timetable_change_canceled)
    LessonChangeKind.SUBSTITUTION -> stringResource(R.string.timetable_change_substitution)
    LessonChangeKind.ROOM_CHANGED -> stringResource(R.string.timetable_change_room)
    LessonChangeKind.ADDED -> stringResource(R.string.timetable_change_added)
}

private fun LessonChangeKind.color(): Color = when (this) {
    LessonChangeKind.NONE -> AccentTeal
    LessonChangeKind.CANCELED -> GradeyColors.Poor
    LessonChangeKind.SUBSTITUTION -> GradeyColors.Average
    LessonChangeKind.ROOM_CHANGED -> GradeyColors.Good
    LessonChangeKind.ADDED -> GradeyColors.SystemPurple
}

private fun ScheduledLesson.formattedTimeRange(): String =
    listOf(hour.beginTime.clockDisplay(), hour.endTime.clockDisplay())
        .filter { it.isNotBlank() }
        .joinToString(" – ")

private fun String.clockDisplay(): String = trim().removePrefix("0")
