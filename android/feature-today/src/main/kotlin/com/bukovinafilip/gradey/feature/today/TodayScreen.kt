package com.bukovinafilip.gradey.feature.today

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.domain.AbsenceRiskLevel
import com.bukovinafilip.gradey.domain.AbsenceRiskSummary
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

private val BackgroundTop = Color(0xFFDDF4F2)
private val BackgroundMiddle = Color(0xFFF0F8F8)
private val BackgroundBottom = Color(0xFFF7F7FA)
private val AccentTeal = Color(0xFF17A185)
private val HeroStart = Color(0xFF16A083)
private val AccentGreen = Color(0xFF1CA46A)
private val AccentDark = Color(0xFF063C36)
private val CardWhite = Color(0xFFFDFDFE)
private val MutedText = Color(0xFF919196)
private val SoftMint = Color(0xFFDDF4EF)
private val SoftGray = Color(0xFFF0F0F2)
private val WarningOrange = Color(0xFFFF8D28)
private val DangerRed = Color(0xFFE5545D)
private val PragueZone = ZoneId.of("Europe/Prague")
private val HourFormatter = DateTimeFormatter.ofPattern("H:mm")

@Composable
fun TodayScreen(
    dashboard: DashboardData,
    absence: AbsenceResponse,
    timetable: TimetableWeek?,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    onOpenMarks: () -> Unit,
    onOpenAbsence: () -> Unit,
    onOpenTimetable: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val subjects = dashboard.marksResponse.subjects
    val overall = GradeMath.formattedAverage(GradeMath.overallAverage(subjects)).replace('.', ',')
    val totalMarks = subjects.sumOf { it.marks.size }
    val absenceRows = AbsenceRiskSummary.make(absence, absence.absencesPerSubject).subjects.take(2)
    val featuredLesson = featuredLesson(timetable)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(BackgroundTop, BackgroundMiddle, BackgroundBottom),
                ),
            ),
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, top = 30.dp, end = 16.dp, bottom = 126.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                TodayHeader(
                    isRefreshing = isRefreshing,
                    onRefresh = onRefresh,
                    onOpenAccount = onOpenAccount,
                    onOpenGradeyTools = onOpenGradeyTools,
                )
            }
            item {
                AverageCard(
                    fullName = dashboard.user?.fullName ?: "Student",
                    overallAverage = overall,
                    subjectCount = subjects.size,
                    markCount = totalMarks,
                )
            }
            item { MarksShortcut(onClick = onOpenMarks) }
            item { NowAndNextCard(featuredLesson = featuredLesson, onClick = onOpenTimetable) }
            item { AbsenceRiskCard(rows = absenceRows, onOpenAbsence = onOpenAbsence) }
            item { AbsencePredictorCard(onPlanAbsence = onOpenAbsence) }
        }
    }
}

@Composable
private fun TodayHeader(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(62.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(44.dp),
            onClick = onOpenGradeyTools,
            shape = CircleShape,
            color = Color(0xFFE9FCFB),
            shadowElevation = 2.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Surface(
                    modifier = Modifier.size(30.dp),
                    shape = CircleShape,
                    color = Color(0xFFCFF3EE),
                ) {
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
            text = "Today",
            color = Color.Black,
            fontSize = 18.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.SemiBold,
        )

        Surface(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .width(106.dp)
                .height(44.dp),
            shape = RoundedCornerShape(25.dp),
            color = Color(0xFFE8FCFA),
            shadowElevation = 2.dp,
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 5.dp),
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
                                contentDescription = "Refresh Today",
                                tint = AccentTeal,
                                modifier = Modifier.size(27.dp),
                            )
                        }
                    }
                }
                Surface(
                    modifier = Modifier.size(34.dp),
                    onClick = onOpenAccount,
                    shape = CircleShape,
                    color = Color(0xFFC9F2EC),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Default.Person,
                            contentDescription = "Open account",
                            tint = AccentTeal,
                            modifier = Modifier.size(23.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AverageCard(
    fullName: String,
    overallAverage: String,
    subjectCount: Int,
    markCount: Int,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(166.dp),
        shape = RoundedCornerShape(20.dp),
        color = Color.Transparent,
        shadowElevation = 4.dp,
    ) {
        Column(
            modifier = Modifier
                .background(Brush.horizontalGradient(listOf(HeroStart, AccentGreen)))
                .padding(horizontal = 24.dp, vertical = 24.dp),
        ) {
            Text(
                text = fullName,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = Color(0xFF021D1A),
                fontSize = 22.sp,
                lineHeight = 27.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(18.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column {
                    Text(
                        text = "Overall average",
                        color = AccentDark,
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = overallAverage,
                        color = Color(0xFF001D19),
                        fontSize = 50.sp,
                        lineHeight = 53.sp,
                        fontWeight = FontWeight.ExtraBold,
                    )
                }
                Column(
                    modifier = Modifier.padding(top = 1.dp),
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = "$subjectCount ${plural(subjectCount, "subject", "subjects")}",
                        color = AccentDark,
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = "$markCount ${plural(markCount, "mark", "marks")}",
                        color = AccentDark,
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

@Composable
private fun MarksShortcut(onClick: () -> Unit) {
    DashboardSurface(
        modifier = Modifier.height(62.dp),
        onClick = onClick,
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconTile(background = SoftMint) {
                Icon(
                    imageVector = Icons.Default.Verified,
                    contentDescription = null,
                    tint = AccentTeal,
                    modifier = Modifier.size(25.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Marks",
                    color = Color.Black,
                    fontSize = 17.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "Averages, subjects, trends, and calculator",
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = MutedText,
                    fontSize = 13.sp,
                    lineHeight = 17.sp,
                )
            }
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = null,
                tint = Color(0xFF858589),
                modifier = Modifier.size(27.dp),
            )
        }
    }
}

@Composable
private fun NowAndNextCard(
    featuredLesson: FeaturedLesson?,
    onClick: () -> Unit,
) {
    DashboardSurface(
        modifier = Modifier.height(96.dp),
        onClick = onClick,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp, vertical = 14.dp),
        ) {
            SectionHeading("NOW AND NEXT")
            Spacer(Modifier.height(9.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconTile(background = SoftGray, size = 32.dp) {
                    Icon(
                        imageVector = Icons.Default.CalendarMonth,
                        contentDescription = null,
                        tint = MutedText,
                        modifier = Modifier.size(20.dp),
                    )
                }
                Spacer(Modifier.width(13.dp))
                Column {
                    Text(
                        text = featuredLesson?.let { if (it.isCurrent) "Now · ${it.lesson.displayTitle()}" else "Next · ${it.lesson.displayTitle()}" }
                            ?: "Timetable unavailable",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = Color.Black,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = featuredLesson?.lesson?.details().orEmpty().ifBlank { "Pull to refresh or open Timetable." },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = MutedText,
                        fontSize = 13.sp,
                        lineHeight = 17.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun AbsenceRiskCard(
    rows: List<com.bukovinafilip.gradey.domain.AbsenceSubjectSummary>,
    onOpenAbsence: () -> Unit,
) {
    DashboardSurface(modifier = Modifier.heightIn(min = 190.dp)) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 15.dp, bottom = 11.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                SectionHeading("ABSENCE RISK")
                ActionPill(text = "Open", onClick = onOpenAbsence)
            }
            Spacer(Modifier.height(5.dp))
            if (rows.isEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 24.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconTile(background = SoftGray) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = null, tint = MutedText)
                    }
                    Spacer(Modifier.width(13.dp))
                    Text("Absence data unavailable", color = MutedText, fontSize = 14.sp)
                }
            } else {
                rows.forEach { row ->
                    val color = row.level.riskColor()
                    RiskRow(
                        subjectName = row.subjectName,
                        percentage = row.absencePercentage,
                        threshold = row.threshold,
                        missesUntilLimit = row.missesUntilLimit,
                        color = color,
                    )
                }
            }
        }
    }
}

@Composable
private fun RiskRow(
    subjectName: String,
    percentage: Double,
    threshold: Double?,
    missesUntilLimit: Int?,
    color: Color,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(62.dp)
            .padding(start = 6.dp, end = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RiskRing(
            progress = if (threshold != null && threshold > 0.0) percentage / threshold else percentage / 100.0,
            color = color,
        )
        Spacer(Modifier.width(3.dp))
        Column(modifier = Modifier.widthIn(max = 214.dp)) {
            Text(
                text = subjectName,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = Color.Black,
                fontSize = 16.sp,
                lineHeight = 19.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = absenceLimitDescription(missesUntilLimit),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = MutedText,
                fontSize = 13.sp,
                lineHeight = 16.sp,
            )
        }
        Spacer(Modifier.weight(1f))
        Spacer(Modifier.width(6.dp))
        Text(
            text = "${percentage.roundToInt()}%",
            color = color,
            fontSize = 17.sp,
            lineHeight = 23.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun RiskRing(progress: Double, color: Color) {
    Canvas(modifier = Modifier.size(58.dp)) {
        val strokeWidth = 6.dp.toPx()
        drawArc(
            color = color.copy(alpha = 0.28f),
            startAngle = -90f,
            sweepAngle = 360f,
            useCenter = false,
            style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
        )
        drawArc(
            color = color,
            startAngle = -90f,
            sweepAngle = (progress.coerceIn(0.0, 1.0) * 360.0).toFloat(),
            useCenter = false,
            style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
        )
    }
}

@Composable
private fun AbsencePredictorCard(onPlanAbsence: () -> Unit) {
    DashboardSurface(modifier = Modifier.height(138.dp)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp, vertical = 15.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                SectionHeading("ABSENCE PREDICTOR")
                ActionPill(text = "Plan absence", onClick = onPlanAbsence)
            }
            Spacer(Modifier.height(13.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconTile(background = SoftGray, size = 38.dp) {
                    Icon(
                        imageVector = Icons.Default.CalendarMonth,
                        contentDescription = null,
                        tint = MutedText,
                        modifier = Modifier.size(22.dp),
                    )
                }
                Spacer(Modifier.width(13.dp))
                Column {
                    Text(
                        text = "No planned absences",
                        color = Color.Black,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = "Plan lessons to preview your absence risk.",
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        color = MutedText,
                        fontSize = 13.sp,
                        lineHeight = 17.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun DashboardSurface(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    if (onClick == null) {
        Surface(
            modifier = modifier.fillMaxWidth(),
            shape = RoundedCornerShape(20.dp),
            color = CardWhite.copy(alpha = 0.98f),
            shadowElevation = 3.dp,
            content = content,
        )
    } else {
        Surface(
            modifier = modifier.fillMaxWidth(),
            onClick = onClick,
            shape = RoundedCornerShape(20.dp),
            color = CardWhite.copy(alpha = 0.98f),
            shadowElevation = 3.dp,
            content = content,
        )
    }
}

@Composable
private fun SectionHeading(text: String) {
    Text(
        text = text,
        color = MutedText,
        fontSize = 13.sp,
        lineHeight = 18.sp,
        letterSpacing = 0.65.sp,
        fontWeight = FontWeight.Bold,
    )
}

@Composable
private fun ActionPill(text: String, onClick: () -> Unit) {
    Surface(
        modifier = Modifier.height(28.dp),
        onClick = onClick,
        shape = RoundedCornerShape(18.dp),
        color = SoftMint,
    ) {
        Box(
            modifier = Modifier.padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = text,
                color = AccentTeal,
                fontSize = 13.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun IconTile(
    background: Color,
    size: androidx.compose.ui.unit.Dp = 38.dp,
    content: @Composable () -> Unit,
) {
    Surface(
        modifier = Modifier.size(size),
        shape = RoundedCornerShape(13.dp),
        color = background,
    ) {
        Box(contentAlignment = Alignment.Center) { content() }
    }
}

private data class FeaturedLesson(
    val lesson: ScheduledLesson,
    val isCurrent: Boolean,
)

private fun featuredLesson(timetable: TimetableWeek?): FeaturedLesson? {
    val today = LocalDate.now(PragueZone).toString()
    val lessons = timetable?.days?.firstOrNull { it.date == today }?.lessons.orEmpty()
    if (lessons.isEmpty()) return null

    val now = LocalTime.now(PragueZone)
    lessons.firstOrNull { lesson ->
        val start = lesson.hour.beginTime.asLocalTime()
        val end = lesson.hour.endTime.asLocalTime()
        start != null && end != null && !now.isBefore(start) && !now.isAfter(end)
    }?.let { return FeaturedLesson(it, isCurrent = true) }

    return lessons.firstOrNull { lesson ->
        lesson.hour.beginTime.asLocalTime()?.isAfter(now) == true
    }?.let { FeaturedLesson(it, isCurrent = false) }
}

private fun String.asLocalTime(): LocalTime? =
    runCatching { LocalTime.parse(trim(), HourFormatter) }.getOrNull()

private fun ScheduledLesson.displayTitle(): String =
    subjectName?.takeIf { it.isNotBlank() } ?: title

private fun ScheduledLesson.details(): String =
    listOf(timeRange.takeIf { it.isNotBlank() }, roomTitle).filterNotNull().joinToString(" · ")

private fun AbsenceRiskLevel.riskColor(): Color = when (this) {
    AbsenceRiskLevel.SAFE -> AccentTeal
    AbsenceRiskLevel.WATCH -> WarningOrange
    AbsenceRiskLevel.HIGH -> WarningOrange
    AbsenceRiskLevel.OVER_LIMIT -> DangerRed
    AbsenceRiskLevel.UNAVAILABLE -> MutedText
}

private fun absenceLimitDescription(missesUntilLimit: Int?): String = when (missesUntilLimit) {
    null -> "Absence limit unavailable"
    0 -> "At or above the absence limit"
    1 -> "1 more missed lesson reaches the limit"
    else -> "$missesUntilLimit more missed lessons reaches the limit"
}

private fun plural(count: Int, singular: String, plural: String): String =
    if (count == 1) singular else plural
