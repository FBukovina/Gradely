package com.bukovinafilip.gradey.feature.absence

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.domain.AbsenceDaySummary
import com.bukovinafilip.gradey.domain.AbsenceMonthSummary
import com.bukovinafilip.gradey.domain.AbsenceRiskSummary
import com.bukovinafilip.gradey.domain.AbsenceSubjectSummary
import com.bukovinafilip.gradey.domain.AbsenceTimeline
import com.bukovinafilip.gradey.domain.AbsenceTimelineSummary
import com.bukovinafilip.gradey.model.AbsenceCounts
import com.bukovinafilip.gradey.model.AbsenceResponse
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max

private val BackgroundTop = Color(0xFFCBDDDD)
private val BackgroundBottom = Color(0xFFF2F2F7)
private val AccentTeal = Color(0xFF17A185)
private val NavigationTeal = Color(0xFF0C967C)
private val ExcusedGreen = Color(0xFF1DA565)
private val RiskOrange = Color(0xFFFF8D28)
private val LateOrange = Color(0xFFD98F10)
private val MissedRed = Color(0xFFD95461)
private val MutedText = Color(0xFF8A8A8E)
private val CardWhite = Color.White
private val DividerColor = Color(0xFFC6C6C8)
private val SoftTeal = Color(0xFFDDF0EC)
private val SoftGreen = Color(0xFFDFF2E9)
private val SoftOrange = Color(0xFFF9EEDD)
private val SoftRed = Color(0xFFF7E4E6)
private val SoftGray = Color(0xFFF2F2F7)
private val ProgressRail = Color(0xFFEFEFF0)
private val EnglishLocale = Locale.ENGLISH
private val DayFormatter = DateTimeFormatter.ofPattern("EEE d. M.", EnglishLocale)
private val MonthFormatter = DateTimeFormatter.ofPattern("MMMM yyyy", EnglishLocale)

private enum class AbsenceMode(val label: String, val description: String) {
    Subjects("Subjects", "Show subjects"),
    Days("By days", "Show by days"),
    Months("By months", "Show by months"),
}

@Composable
fun AbsenceScreen(
    response: AbsenceResponse,
    studentName: String,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var mode by rememberSaveable { mutableStateOf(AbsenceMode.Subjects) }
    val timeline = remember(response) { AbsenceTimeline.make(response) }
    val riskSummary = remember(response) {
        AbsenceRiskSummary.make(response, response.absencesPerSubject)
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(BackgroundBottom),
    ) {
        AbsenceBackgroundGlow()
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, top = 28.dp, end = 16.dp, bottom = 126.dp),
        ) {
            item {
                AbsenceHeader(
                    isRefreshing = isRefreshing,
                    onRefresh = onRefresh,
                    onOpenAccount = onOpenAccount,
                    onOpenGradeyTools = onOpenGradeyTools,
                )
            }
            item { Spacer(Modifier.height(12.dp)) }
            item {
                AbsenceSummaryCard(
                    studentName = studentName,
                    counts = timeline.total,
                    threshold = normalizedThreshold(response.percentageThreshold),
                )
            }
            item { Spacer(Modifier.height(11.dp)) }
            item { AbsenceModePicker(selected = mode, onSelect = { mode = it }) }
            when (mode) {
                AbsenceMode.Subjects -> {
                    item { Spacer(Modifier.height(12.dp)) }
                    item { SubjectsCard(riskSummary.subjects) }
                }

                AbsenceMode.Days -> {
                    item { Spacer(Modifier.height(12.dp)) }
                    item { DaysCard(timeline) }
                }

                AbsenceMode.Months -> {
                    item { Spacer(Modifier.height(8.dp)) }
                    item { SectionHeading("HOURS BY MONTH") }
                    item { Spacer(Modifier.height(8.dp)) }
                    item { MonthsChartCard(timeline.months) }
                    item { Spacer(Modifier.height(9.dp)) }
                    item { MonthsCard(timeline) }
                }
            }
        }
    }
}

@Composable
private fun AbsenceHeader(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp),
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
            text = "Absence",
            color = Color.Black,
            fontSize = 17.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.SemiBold,
        )

        Surface(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .width(105.dp)
                .height(44.dp),
            shape = RoundedCornerShape(22.dp),
            color = Color(0xFFDCFAF6),
            shadowElevation = 2.dp,
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 7.dp, vertical = 5.dp),
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
                                contentDescription = "Refresh Absence",
                                tint = AccentTeal,
                                modifier = Modifier.size(27.dp),
                            )
                        }
                    }
                }
                Surface(
                    modifier = Modifier.size(32.dp),
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
private fun AbsenceSummaryCard(
    studentName: String,
    counts: AbsenceCounts,
    threshold: Double?,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(140.dp),
        shape = RoundedCornerShape(20.dp),
        color = CardWhite,
        shadowElevation = 2.dp,
    ) {
        Column(modifier = Modifier.padding(start = 16.dp, top = 15.dp, end = 16.dp, bottom = 12.dp)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(46.dp),
                verticalAlignment = Alignment.Top,
            ) {
                AbsenceIconTile()
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(
                        text = "Absence",
                        color = Color.Black,
                        fontSize = 17.sp,
                        lineHeight = 21.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = studentName.ifBlank { "Student" },
                        color = MutedText,
                        fontSize = 17.sp,
                        lineHeight = 20.sp,
                    )
                }
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = counts.total.toString(),
                        color = AccentTeal,
                        fontSize = 24.sp,
                        lineHeight = 28.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = "hours",
                        color = MutedText,
                        fontSize = 14.sp,
                        lineHeight = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            SummaryPills(counts)
            Spacer(Modifier.height(8.dp))
            Text(
                text = threshold?.let { "School limit: ${formatWhole(it)} %" } ?: "School limit unavailable",
                color = MutedText,
                fontSize = 14.sp,
                lineHeight = 20.sp,
            )
        }
    }
}

@Composable
private fun AbsenceIconTile() {
    Surface(
        modifier = Modifier.size(46.dp),
        shape = RoundedCornerShape(13.dp),
        color = SoftTeal,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                imageVector = Icons.Default.CalendarMonth,
                contentDescription = null,
                tint = AccentTeal,
                modifier = Modifier.size(25.dp),
            )
            Icon(
                imageVector = Icons.Default.Error,
                contentDescription = null,
                tint = AccentTeal,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 8.dp, bottom = 8.dp)
                    .size(11.dp),
            )
        }
    }
}

@Composable
private fun SummaryPills(counts: AbsenceCounts) {
    Row {
        Box(modifier = Modifier.width(68.dp)) { CountPill(AttendanceKind.Unresolved, counts.unsolved) }
        Box(modifier = Modifier.width(68.dp)) { CountPill(AttendanceKind.Excused, counts.ok) }
        CountPill(AttendanceKind.Late, counts.late)
    }
}

@Composable
private fun AbsenceModePicker(
    selected: AbsenceMode,
    onSelect: (AbsenceMode) -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(33.dp),
        shape = RoundedCornerShape(17.dp),
        color = Color(0x0D000000),
    ) {
        Row(modifier = Modifier.padding(2.dp)) {
            AbsenceMode.entries.forEach { mode ->
                Surface(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxSize()
                        .selectable(
                            selected = selected == mode,
                            role = Role.Tab,
                            onClick = { onSelect(mode) },
                        )
                        .semantics { contentDescription = mode.description },
                    shape = RoundedCornerShape(15.dp),
                    color = if (selected == mode) Color.White else Color.Transparent,
                    shadowElevation = if (selected == mode) 1.dp else 0.dp,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            text = mode.label,
                            color = Color.Black,
                            fontSize = 15.sp,
                            lineHeight = 18.sp,
                            fontWeight = if (selected == mode) FontWeight.SemiBold else FontWeight.Medium,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SubjectsCard(subjects: List<AbsenceSubjectSummary>) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = CardWhite,
        shadowElevation = 1.dp,
    ) {
        if (subjects.isEmpty()) {
            EmptyState("No subject absence data")
        } else {
            Column {
                subjects.forEachIndexed { index, subject ->
                    SubjectRow(subject)
                    if (index != subjects.lastIndex) {
                        HorizontalDivider(color = Color(0xFFC6C6C8), thickness = 0.33.dp)
                    }
                }
            }
        }
    }
}

@Composable
private fun SubjectRow(subject: AbsenceSubjectSummary) {
    val warning = subject.absencePercentage >= 15.0
    val color = if (warning) RiskOrange else AccentTeal
    val threshold = subject.threshold ?: 100.0
    val progress = (subject.absencePercentage / threshold).toFloat().coerceIn(0f, 1f)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(81.dp)
            .padding(horizontal = 12.dp, vertical = 9.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = subject.subjectName,
                modifier = Modifier.weight(1f),
                color = Color.Black,
                fontSize = 17.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "${formatOneDecimal(subject.absencePercentage)} %",
                color = color,
                fontSize = 17.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Spacer(Modifier.height(5.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp)
                .background(ProgressRail, RoundedCornerShape(3.dp)),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(progress)
                    .height(6.dp)
                    .background(color, RoundedCornerShape(3.dp)),
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = buildAnnotatedString {
                append("${subject.base} of ${subject.lessonsCount} lessons missed · ")
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                    append(subject.missesUntilLimit?.let { "$it more until the limit" } ?: "limit unavailable")
                }
            },
            color = MutedText,
            fontSize = 13.sp,
            lineHeight = 16.sp,
            maxLines = 1,
        )
    }
}

@Composable
private fun DaysCard(timeline: AbsenceTimelineSummary) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = CardWhite,
        shadowElevation = 1.dp,
    ) {
        Column {
            TotalsRow(timeline.total)
            timeline.days.forEach { day ->
                HorizontalDivider(color = DividerColor, thickness = 0.33.dp)
                DayRow(day)
            }
            if (timeline.days.isEmpty()) EmptyState("No absence days")
        }
    }
}

@Composable
private fun TotalsRow(counts: AbsenceCounts) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .background(SoftGray)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "Total",
            modifier = Modifier.weight(1f),
            color = Color.Black,
            fontSize = 17.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.Bold,
        )
        CompactCountPills(counts)
        Text(
            text = counts.total.toString(),
            modifier = Modifier.width(34.dp),
            color = Color.Black,
            fontSize = 17.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun DayRow(day: AbsenceDaySummary) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = day.date.format(DayFormatter),
            modifier = Modifier.weight(1f),
            color = Color.Black,
            fontSize = 16.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.SemiBold,
        )
        CompactCountPills(day.counts)
        Text(
            text = day.counts.total.toString(),
            modifier = Modifier.width(34.dp),
            color = Color.Black,
            fontSize = 16.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun CompactCountPills(counts: AbsenceCounts) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        if (counts.unsolved > 0) CountPill(AttendanceKind.Unresolved, counts.unsolved)
        if (counts.ok > 0) CountPill(AttendanceKind.Excused, counts.ok)
        if (counts.missed > 0) CountPill(AttendanceKind.Missed, counts.missed)
        if (counts.late > 0) CountPill(AttendanceKind.Late, counts.late)
        if (counts.soon > 0) CountPill(AttendanceKind.Other, counts.soon)
        if (counts.school > 0) CountPill(AttendanceKind.Other, counts.school)
        if (counts.distanceTeaching > 0) CountPill(AttendanceKind.Other, counts.distanceTeaching)
    }
}

@Composable
private fun SectionHeading(text: String) {
    Text(
        text = text,
        color = MutedText,
        fontSize = 14.sp,
        lineHeight = 18.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.6.sp,
    )
}

@Composable
private fun MonthsChartCard(months: List<AbsenceMonthSummary>) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(260.dp),
        shape = RoundedCornerShape(20.dp),
        color = CardWhite,
        shadowElevation = 1.dp,
    ) {
        Column {
            MonthBars(
                months = months,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(189.dp),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(25.dp)
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                LegendPill(AttendanceKind.Unresolved, "Unresolved absence")
                LegendPill(AttendanceKind.Excused, "Excused absence")
            }
            Spacer(Modifier.height(5.dp))
            Row(modifier = Modifier.padding(start = 16.dp)) {
                LegendPill(AttendanceKind.Late, "Late arrivals")
            }
        }
    }
}

@Composable
private fun MonthBars(
    months: List<AbsenceMonthSummary>,
    modifier: Modifier = Modifier,
) {
    val visibleMonths = months.takeLast(5)
    val maxMonth = visibleMonths.maxOfOrNull { it.counts.total } ?: 0
    val axisMax = max(10, ceil(maxMonth / 5.0).toInt() * 5)
    Box(
        modifier = modifier.semantics {
            contentDescription = visibleMonths.joinToString(
                prefix = "Hours by month: ",
                separator = ", ",
            ) { "${it.month.month.name.lowercase().replaceFirstChar(Char::uppercase)} ${it.counts.total}" }
        },
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val gridLeft = 16.dp.toPx()
            val gridRight = size.width - 32.dp.toPx()
            val plotTop = 16.dp.toPx()
            val plotBottom = 159.dp.toPx()
            val plotHeight = plotBottom - plotTop
            val gridColor = Color(0xFFE6E6E8)
            listOf(plotTop, plotTop + plotHeight / 2f, plotBottom).forEach { y ->
                drawLine(gridColor, Offset(gridLeft, y), Offset(gridRight, y), strokeWidth = 0.7.dp.toPx())
            }

            if (visibleMonths.isNotEmpty()) {
                val barRegionLeft = 13.5.dp.toPx()
                val barRegionRight = size.width - 31.5.dp.toPx()
                val slotWidth = (barRegionRight - barRegionLeft) / visibleMonths.size
                val barWidth = minOf(44.dp.toPx(), slotWidth * 0.72f)
                visibleMonths.forEachIndexed { index, month ->
                    val left = barRegionLeft + slotWidth * index + (slotWidth - barWidth) / 2f
                    drawMonthBar(
                        counts = month.counts,
                        left = left,
                        bottom = plotBottom,
                        width = barWidth,
                        plotHeight = plotHeight,
                        axisMax = axisMax,
                    )
                }
            }
        }

        Text(
            text = axisMax.toString(),
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(end = 9.dp)
                .offset(y = 7.dp),
            color = MutedText,
            fontSize = 13.sp,
        )
        Text(
            text = (axisMax / 2).toString(),
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(end = 9.dp)
                .offset(y = 78.dp),
            color = MutedText,
            fontSize = 13.sp,
        )
        Text(
            text = "0",
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(end = 9.dp)
                .offset(y = 150.dp),
            color = MutedText,
            fontSize = 13.sp,
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(end = 45.dp)
                .offset(x = (-9.5).dp, y = 160.dp)
                .height(20.dp),
        ) {
            visibleMonths.forEach { month ->
                Text(
                    text = month.month.month.name.take(1),
                    modifier = Modifier.weight(1f),
                    color = MutedText,
                    fontSize = 13.sp,
                    lineHeight = 17.sp,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

private fun DrawScope.drawMonthBar(
    counts: AbsenceCounts,
    left: Float,
    bottom: Float,
    width: Float,
    plotHeight: Float,
    axisMax: Int,
) {
    val segments = listOf(
        counts.ok to ExcusedGreen,
        counts.unsolved to AccentTeal,
        counts.missed to MissedRed,
        counts.late to LateOrange,
        (counts.soon + counts.school + counts.distanceTeaching) to NavigationTeal,
    ).filter { it.first > 0 }
    var currentBottom = bottom
    segments.forEachIndexed { index, (value, color) ->
        val height = plotHeight * value.toFloat() / axisMax.toFloat()
        val top = currentBottom - height
        if (index == segments.lastIndex) {
            drawRoundRect(
                color = color,
                topLeft = Offset(left, top),
                size = Size(width, height + if (segments.size > 1) 2.dp.toPx() else 0f),
                cornerRadius = CornerRadius(3.dp.toPx(), 3.dp.toPx()),
            )
        } else {
            drawRect(color = color, topLeft = Offset(left, top), size = Size(width, height))
        }
        currentBottom = top
    }
}

@Composable
private fun MonthsCard(timeline: AbsenceTimelineSummary) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = CardWhite,
        shadowElevation = 1.dp,
    ) {
        Column {
            TotalsRow(timeline.total)
            timeline.months.forEach { month ->
                HorizontalDivider(color = DividerColor, thickness = 0.33.dp)
                MonthRow(month)
            }
            if (timeline.months.isEmpty()) EmptyState("No monthly absence data")
        }
    }
}

@Composable
private fun MonthRow(month: AbsenceMonthSummary) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(49.dp)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = month.month.format(MonthFormatter),
            modifier = Modifier.weight(1f),
            color = Color.Black,
            fontSize = 16.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.SemiBold,
        )
        CompactCountPills(month.counts)
        Text(
            text = month.counts.total.toString(),
            modifier = Modifier.width(34.dp),
            color = Color.Black,
            fontSize = 16.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.End,
        )
    }
}

private enum class AttendanceKind(
    val foreground: Color,
    val background: Color,
) {
    Unresolved(AccentTeal, SoftTeal),
    Excused(ExcusedGreen, SoftGreen),
    Late(LateOrange, SoftOrange),
    Missed(MissedRed, SoftRed),
    Other(NavigationTeal, SoftTeal),
}

@Composable
private fun CountPill(kind: AttendanceKind, count: Int) {
    Surface(
        modifier = Modifier.height(25.dp),
        shape = RoundedCornerShape(13.dp),
        color = kind.background,
        contentColor = kind.foreground,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            AttendanceIcon(kind)
            Text(
                text = count.toString(),
                color = kind.foreground,
                fontSize = 14.sp,
                lineHeight = 17.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun LegendPill(kind: AttendanceKind, label: String) {
    Surface(
        modifier = Modifier.height(25.dp),
        shape = RoundedCornerShape(13.dp),
        color = kind.background,
        contentColor = kind.foreground,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            AttendanceIcon(kind)
            Text(
                text = label,
                color = kind.foreground,
                fontSize = 13.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun AttendanceIcon(kind: AttendanceKind) {
    when (kind) {
        AttendanceKind.Unresolved -> Text("?", color = kind.foreground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        AttendanceKind.Excused -> Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(14.dp))
        AttendanceKind.Late -> Text("P", color = kind.foreground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        AttendanceKind.Missed -> Text("!", color = kind.foreground, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        AttendanceKind.Other -> Text("•", color = kind.foreground, fontSize = 13.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun EmptyState(text: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(80.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = text, color = MutedText, fontSize = 14.sp)
    }
}

private fun normalizedThreshold(value: Double?): Double? =
    value?.let { if (it in 0.0..1.0) it * 100.0 else it }?.takeIf { it > 0.0 }

private fun formatWhole(value: Double): String =
    if (value % 1.0 == 0.0) value.toInt().toString() else String.format(Locale.US, "%.1f", value)

private fun formatOneDecimal(value: Double): String = String.format(Locale.US, "%.1f", value)

@Composable
private fun AbsenceBackgroundGlow() {
    Canvas(modifier = Modifier.fillMaxSize()) {
        drawRect(
            brush = Brush.verticalGradient(
                colorStops = arrayOf(
                    0f to BackgroundTop,
                    0.32f to BackgroundBottom,
                    1f to BackgroundBottom,
                ),
            ),
        )
        drawRect(
            brush = Brush.radialGradient(
                colors = listOf(Color(0x35309C89), Color.Transparent),
                center = Offset(size.width, size.height * 0.24f),
                radius = size.width * 0.75f,
            ),
        )
        drawRect(
            brush = Brush.radialGradient(
                colors = listOf(Color(0x265EAEB5), Color.Transparent),
                center = Offset(0f, size.height * 0.59f),
                radius = size.width * 0.70f,
            ),
        )
    }
}
