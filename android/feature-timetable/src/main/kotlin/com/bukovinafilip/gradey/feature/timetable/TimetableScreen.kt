package com.bukovinafilip.gradey.feature.timetable

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.MeetingRoom
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private val BackgroundTop = Color(0xFFCBDDDD)
private val BackgroundBottom = Color(0xFFF2F2F7)
private val AccentTeal = Color(0xFF17A185)
private val HeroStart = Color(0xFF18A182)
private val HeroEnd = Color(0xFF1CA567)
private val MutedText = Color(0xFF8A8A8E)
private val MutedLight = Color(0xFFB9BAC0)
private val SubjectTile = Color(0xFFDEF1ED)
private val NoticeRed = Color(0xFFD83E4F)
private val DividerColor = Color(0xFFC6C6C8)
private val EnglishLocale = Locale.ENGLISH
private val WeekMonthFormatter = DateTimeFormatter.ofPattern("MMM", EnglishLocale)
private val WeekdayFormatter = DateTimeFormatter.ofPattern("EEE", EnglishLocale)

private data class TimetableDaySlot(
    val date: LocalDate,
    val day: ScheduledDay?,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimetableScreen(
    week: TimetableWeek?,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onChangeWeek: (String) -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val monday = remember(week?.weekStart) { weekMonday(week) }
    val daySlots = remember(week, monday) { timetableDaySlots(week, monday) }
    val initialDate = daySlots.firstOrNull { it.day?.isToday == true }?.date ?: monday
    var selectedDate by rememberSaveable(week?.weekStart) { mutableStateOf(initialDate.toString()) }
    var selectedLesson by remember { mutableStateOf<ScheduledLesson?>(null) }
    val selectedDay = daySlots.firstOrNull { it.date.toString() == selectedDate }?.day

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(BackgroundBottom),
    ) {
        TimetableBackgroundGlow()
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
                enabled = !isRefreshing,
                onPrevious = { onChangeWeek(monday.minusWeeks(1).toString()) },
                onNext = { onChangeWeek(monday.plusWeeks(1).toString()) },
            )
            Spacer(Modifier.height(8.dp))
            DayStrip(
                daySlots = daySlots,
                selectedDate = selectedDate,
                onSelect = { selectedDate = it.toString() },
            )
            Spacer(Modifier.height(11.dp))
            HorizontalDivider(thickness = 0.5.dp, color = DividerColor.copy(alpha = 0.62f))
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
            contentColor = Color.Black,
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
private fun TimetableHeader(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(44.dp),
            onClick = onOpenGradeyTools,
            shape = CircleShape,
            color = Color(0xFFE8FAFB),
            shadowElevation = 2.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Surface(modifier = Modifier.size(30.dp), shape = CircleShape, color = Color(0xFFC7ECE9)) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Default.AutoAwesome,
                            contentDescription = "Open Gradey tools",
                            tint = AccentTeal,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            }
        }

        Text(
            text = "Timetable",
            color = Color.Black,
            fontSize = 17.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.SemiBold,
        )

        Surface(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .width(106.dp)
                .height(44.dp),
            shape = RoundedCornerShape(22.dp),
            color = Color(0xFFDCFAF6),
            shadowElevation = 2.dp,
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 7.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Surface(
                    modifier = Modifier.size(34.dp),
                    onClick = onRefresh,
                    enabled = !isRefreshing,
                    shape = CircleShape,
                    color = Color.Transparent,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        if (isRefreshing) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(21.dp),
                                color = AccentTeal,
                                strokeWidth = 2.5.dp,
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Default.Refresh,
                                contentDescription = "Refresh timetable",
                                tint = AccentTeal,
                                modifier = Modifier.size(27.dp),
                            )
                        }
                    }
                }
                Surface(
                    modifier = Modifier.size(36.dp),
                    onClick = onOpenAccount,
                    shape = CircleShape,
                    color = Color(0xFFBDECE4),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Default.Person,
                            contentDescription = "Open account",
                            tint = AccentTeal,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun WeekNavigator(
    monday: LocalDate,
    enabled: Boolean,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(40.dp)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        WeekArrow(
            description = "Previous week",
            enabled = enabled,
            onClick = onPrevious,
            modifier = Modifier.align(Alignment.CenterStart),
        ) {
            Icon(Icons.Default.ChevronLeft, contentDescription = null, tint = AccentTeal, modifier = Modifier.size(24.dp))
        }
        Text(
            text = formatWeekRange(monday),
            color = Color.Black,
            fontSize = 18.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.SemiBold,
        )
        WeekArrow(
            description = "Next week",
            enabled = enabled,
            onClick = onNext,
            modifier = Modifier.align(Alignment.CenterEnd),
        ) {
            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = AccentTeal, modifier = Modifier.size(24.dp))
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
    Surface(
        modifier = modifier
            .size(40.dp)
            .semantics { contentDescription = description },
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        color = Color(0xFFBFE4DF).copy(alpha = if (enabled) 0.72f else 0.45f),
    ) {
        Box(contentAlignment = Alignment.Center) { icon() }
    }
}

@Composable
private fun DayStrip(
    daySlots: List<TimetableDaySlot>,
    selectedDate: String,
    onSelect: (LocalDate) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(66.dp)
            .padding(start = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        daySlots.forEach { slot ->
            val selected = slot.date.toString() == selectedDate
            val description = "${slot.date.format(WeekdayFormatter)}, ${slot.date.dayOfMonth}"
            val shape = RoundedCornerShape(17.dp)
            Box(
                modifier = Modifier
                    .size(width = 52.dp, height = 66.dp)
                    .clip(shape)
                    .background(
                        if (selected) {
                            Brush.horizontalGradient(listOf(HeroStart, HeroEnd))
                        } else {
                            Brush.linearGradient(listOf(Color.White, Color.White))
                        },
                    )
                    .clickable(
                        role = Role.Tab,
                        onClickLabel = "Show $description",
                        onClick = { onSelect(slot.date) },
                    )
                    .semantics {
                        contentDescription = "$description${if (selected) ", selected" else ""}"
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
                        text = slot.date.dayOfWeek.name.take(3),
                        color = Color.Black,
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = slot.date.dayOfMonth.toString(),
                        color = Color.Black,
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
                    color = Color.White,
                    shadowElevation = 2.dp,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            text = if (isLoaded) "No lessons" else "Timetable unavailable · Pull to refresh",
                            color = MutedText,
                            fontSize = 15.sp,
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
    val hasTopic = !lesson.theme.isNullOrBlank()
    val hasChange = lesson.changeKind != LessonChangeKind.NONE || !lesson.changeDescription.isNullOrBlank()
    val rowHeight = if (hasTopic || hasChange) 83.dp else 68.dp
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
                .semantics {
                    contentDescription = buildString {
                        append("Open ${lesson.subjectDisplayName()} lesson details, ${lesson.formattedTimeRange()}")
                        lesson.changeDescription?.takeIf { it.isNotBlank() }?.let { append(", $it") }
                    }
                },
            onClick = onClick,
            shape = RoundedCornerShape(20.dp),
            color = if (isCanceled) Color(0xFFFFF1F2) else Color.White,
            shadowElevation = 1.dp,
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(46.dp)
                        .background(SubjectTile, RoundedCornerShape(12.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = lesson.subjectAbbrev ?: lesson.subjectDisplayName().take(2),
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
                        text = lesson.subjectDisplayName(),
                        color = Color.Black,
                        fontSize = 18.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.MeetingRoom,
                            contentDescription = null,
                            tint = MutedText,
                            modifier = Modifier.size(15.dp),
                        )
                        Text(
                            text = lesson.roomAbbrev ?: lesson.roomName.orEmpty(),
                            color = MutedText,
                            fontSize = 15.sp,
                            lineHeight = 18.sp,
                            maxLines = 1,
                        )
                        Icon(
                            imageVector = Icons.Default.Person,
                            contentDescription = null,
                            tint = MutedText,
                            modifier = Modifier.size(16.dp),
                        )
                        Text(
                            text = lesson.teacherName ?: lesson.teacherAbbrev.orEmpty(),
                            color = MutedText,
                            fontSize = 15.sp,
                            lineHeight = 18.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    (lesson.changeDescription?.takeIf { it.isNotBlank() }
                        ?: lesson.theme?.takeIf { it.isNotBlank() })?.let { secondaryText ->
                        Text(
                            text = secondaryText,
                            color = when (lesson.changeKind) {
                                LessonChangeKind.CANCELED -> Color(0xFFD95461)
                                LessonChangeKind.NONE -> MutedText
                                else -> Color(0xFFD98F10)
                            },
                            fontSize = 13.sp,
                            lineHeight = 17.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
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
            color = Color.Black,
            fontSize = 18.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = lesson.hour.beginTime.clockDisplay(),
            color = MutedText,
            fontSize = 13.sp,
            lineHeight = 16.sp,
            fontWeight = FontWeight.Medium,
        )
        Text(
            text = lesson.hour.endTime.clockDisplay(),
            color = MutedLight,
            fontSize = 13.sp,
            lineHeight = 16.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun LessonDetailSheet(lesson: ScheduledLesson) {
    val hasTopic = !lesson.theme.isNullOrBlank()
    val hasChange = !lesson.changeDescription.isNullOrBlank()
    val detailRowCount = 2 + (if (hasTopic) 1 else 0) + (if (hasChange) 1 else 0)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(452.dp)
            .clip(RoundedCornerShape(48.dp))
            .background(
                Brush.verticalGradient(
                    colorStops = arrayOf(
                        0f to Color(0xFFD3E7E7),
                        0.26f to Color(0xFFC4E1DD),
                        0.68f to Color(0xFFEDF1F3),
                        1f to BackgroundBottom,
                    ),
                ),
            ),
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(Color(0x4930A78E), Color.Transparent),
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
                    .background(Color(0xFF83A5A3), RoundedCornerShape(3.dp)),
            )
            Spacer(Modifier.height(16.dp))
            Text(
                text = lesson.subjectDisplayName(),
                color = Color.Black,
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
                        contentDescription = "${lesson.subjectDisplayName()}, ${lesson.formattedTimeRange()}"
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
                        text = lesson.subjectDisplayName(),
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
                color = Color.White,
                shadowElevation = 1.dp,
            ) {
                Column(
                    modifier = Modifier.padding(start = 20.dp, top = 13.dp, end = 20.dp, bottom = 11.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    DetailRow(
                        icon = { Icon(Icons.Default.Person, contentDescription = null) },
                        label = "Teacher",
                        value = lesson.teacherName ?: lesson.teacherAbbrev ?: "—",
                    )
                    DetailRow(
                        icon = { Icon(Icons.Outlined.MeetingRoom, contentDescription = null) },
                        label = "Room",
                        value = lesson.roomName ?: lesson.roomAbbrev ?: "—",
                    )
                    lesson.theme?.takeIf { it.isNotBlank() }?.let { topic ->
                        DetailRow(
                            icon = { Icon(Icons.AutoMirrored.Outlined.MenuBook, contentDescription = null) },
                            label = "Topic",
                            value = topic,
                        )
                    }
                    lesson.changeDescription?.takeIf { it.isNotBlank() }?.let { change ->
                        DetailRow(
                            icon = { Icon(Icons.Default.Info, contentDescription = null) },
                            label = "Change",
                            value = change,
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
                color = MutedText,
                fontSize = 13.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = value,
                color = Color.Black,
                fontSize = 17.sp,
                lineHeight = 20.sp,
                fontWeight = FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun TimetableBackgroundGlow() {
    Canvas(modifier = Modifier.fillMaxSize()) {
        drawRect(
            brush = Brush.verticalGradient(
                colorStops = arrayOf(
                    0f to BackgroundTop,
                    0.34f to BackgroundBottom,
                    1f to BackgroundBottom,
                ),
            ),
        )
        drawRect(
            brush = Brush.radialGradient(
                colors = listOf(Color(0x3830A78E), Color.Transparent),
                center = Offset(size.width, size.height * 0.22f),
                radius = size.width * 0.78f,
            ),
        )
        drawRect(
            brush = Brush.radialGradient(
                colors = listOf(Color(0x245EAEB5), Color.Transparent),
                center = Offset(0f, size.height * 0.56f),
                radius = size.width * 0.72f,
            ),
        )
    }
}

private fun timetableDaySlots(week: TimetableWeek?, monday: LocalDate): List<TimetableDaySlot> {
    val byDate = week?.days.orEmpty().mapNotNull { day ->
        day.date?.let { date -> runCatching { LocalDate.parse(date) }.getOrNull()?.let { it to day } }
    }.toMap()
    val byWeekday = week?.days.orEmpty().associateBy { it.dayOfWeek }
    return (0L..4L).map { offset ->
        val date = monday.plusDays(offset)
        TimetableDaySlot(
            date = date,
            day = byDate[date] ?: byWeekday[date.dayOfWeek.value],
        )
    }
}

private fun weekMonday(week: TimetableWeek?): LocalDate {
    val parsed = week?.weekStart?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
    return TimetableDates.monday(parsed ?: LocalDate.now())
}

private fun formatWeekRange(monday: LocalDate): String {
    val friday = monday.plusDays(4)
    return if (monday.month == friday.month) {
        "${monday.format(WeekMonthFormatter)} ${monday.dayOfMonth}–${friday.dayOfMonth}"
    } else {
        "${monday.format(WeekMonthFormatter)} ${monday.dayOfMonth}–${friday.format(WeekMonthFormatter)} ${friday.dayOfMonth}"
    }
}

private fun ScheduledLesson.subjectDisplayName(): String = subjectName ?: subjectAbbrev ?: "Lesson"

private fun ScheduledLesson.formattedTimeRange(): String =
    listOf(hour.beginTime.clockDisplay(), hour.endTime.clockDisplay())
        .filter { it.isNotBlank() }
        .joinToString(" – ")

private fun String.clockDisplay(): String = trim().removePrefix("0")
