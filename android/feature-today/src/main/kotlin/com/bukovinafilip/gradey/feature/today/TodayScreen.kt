package com.bukovinafilip.gradey.feature.today

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.domain.AbsenceRiskLevel
import com.bukovinafilip.gradey.domain.AbsenceRiskSummary
import com.bukovinafilip.gradey.domain.GradeHistoryTrends
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.domain.GradeTrendRange
import com.bukovinafilip.gradey.domain.SubjectGradeTrend
import com.bukovinafilip.gradey.domain.TodayMealState
import com.bukovinafilip.gradey.domain.TodayMeals
import com.bukovinafilip.gradey.domain.TodayNewMark
import com.bukovinafilip.gradey.domain.TodayNewMarks
import com.bukovinafilip.gradey.domain.TodayPresentationState
import com.bukovinafilip.gradey.domain.TodayTimetableState
import com.bukovinafilip.gradey.domain.TodayTimetableSummaries
import com.bukovinafilip.gradey.domain.TodayTimetableSummary
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.NewMarkEvent
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.TimetableWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
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

@Composable
fun TodayStateScreen(
    state: TodayPresentationState,
    errorMessage: String?,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(BackgroundTop, BackgroundMiddle, BackgroundBottom),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 520.dp)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = stringResource(R.string.today_title),
                color = AccentDark,
                fontSize = 30.sp,
                lineHeight = 36.sp,
                fontWeight = FontWeight.Bold,
            )
            DashboardSurface(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 28.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (state == TodayPresentationState.INITIAL_LOADING) {
                        CircularProgressIndicator(color = AccentTeal)
                        Text(
                            text = stringResource(R.string.today_loading),
                            color = Color.Black,
                            fontSize = 18.sp,
                            lineHeight = 23.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = stringResource(R.string.today_loading_subtitle),
                            color = MutedText,
                            textAlign = TextAlign.Center,
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Default.CalendarMonth,
                            contentDescription = null,
                            tint = MutedText,
                            modifier = Modifier.size(34.dp),
                        )
                        Text(
                            text = if (errorMessage == null) {
                                stringResource(R.string.today_no_data)
                            } else {
                                stringResource(R.string.today_load_failed)
                            },
                            color = Color.Black,
                            fontSize = 18.sp,
                            lineHeight = 23.sp,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            text = errorMessage ?: stringResource(R.string.today_no_data_subtitle),
                            color = MutedText,
                            textAlign = TextAlign.Center,
                        )
                        Button(onClick = onRetry) {
                            Text(stringResource(R.string.today_retry))
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TodayScreen(
    dashboard: DashboardData,
    absence: AbsenceResponse,
    timetable: TimetableWeek?,
    stravaMenu: StravaCZMenu?,
    isMealsConnected: Boolean,
    cloudNewMarkEvents: List<NewMarkEvent> = emptyList(),
    gradeTrends: List<SubjectGradeTrend> = emptyList(),
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    onOpenMarks: () -> Unit,
    onOpenAbsence: () -> Unit,
    onOpenTimetable: () -> Unit,
    onOpenMeals: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showsTrendDetails by rememberSaveable { mutableStateOf(false) }
    var selectedTrendRangeName by rememberSaveable { mutableStateOf(GradeTrendRange.NINETY_DAYS.name) }
    val todayListState = rememberLazyListState()
    val subjects = dashboard.marksResponse.subjects
    val overall = GradeMath.formattedAverage(GradeMath.overallAverage(subjects)).replace('.', ',')
    val totalMarks = subjects.sumOf { it.marks.size }
    val absenceSummary = remember(absence) {
        AbsenceRiskSummary.make(absence, absence.absencesPerSubject)
    }
    val absenceRows = absenceSummary.subjects.take(3)
    val timetableSummary = TodayTimetableSummaries.resolve(timetable)
    val mealState = remember(stravaMenu, isMealsConnected) {
        TodayMeals.resolve(
            isConnected = isMealsConnected,
            menu = stravaMenu,
            today = LocalDate.now(PragueZone),
        )
    }
    val newMarks = remember(subjects, cloudNewMarkEvents) {
        TodayNewMarks.resolve(subjects, cloudNewMarkEvents, PragueZone).take(3)
    }
    val topTrends = remember(gradeTrends) {
        gradeTrends.filter { (it.averageDelta ?: 0.0) != 0.0 }.take(4)
    }

    BackHandler(enabled = showsTrendDetails) { showsTrendDetails = false }
    if (showsTrendDetails) {
        GradeTrendsScreen(
            trends = gradeTrends,
            selectedRangeName = selectedTrendRangeName,
            onRangeSelected = { selectedTrendRangeName = it.name },
            onBack = { showsTrendDetails = false },
            modifier = modifier,
        )
        return
    }

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
            state = todayListState,
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
            if (subjects.isEmpty()) {
                item { EmptyDashboardCard() }
            }
            item { MarksShortcut(onClick = onOpenMarks) }
            item { NowAndNextCard(summary = timetableSummary, onClick = onOpenTimetable) }
            item {
                AbsenceRiskCard(
                    rows = absenceRows,
                    isThresholdUnavailable = absenceSummary.isThresholdUnavailable,
                    onOpenAbsence = onOpenAbsence,
                )
            }
            item { LunchCard(state = mealState, onOpenMeals = onOpenMeals) }
            item { AbsencePredictorCard(onPlanAbsence = onOpenAbsence) }
            item {
                NewMarksAndTrendsCard(
                    newMarks = newMarks,
                    trends = topTrends,
                    onOpenMarks = onOpenMarks,
                    onOpenTrends = { showsTrendDetails = true },
                )
            }
        }
    }
}

@Composable
private fun LunchCard(
    state: TodayMealState,
    onOpenMeals: () -> Unit,
) {
    DashboardSurface(modifier = Modifier.heightIn(min = 116.dp)) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 15.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                SectionHeading(stringResource(R.string.today_lunch).uppercase(Locale.getDefault()))
                ActionPill(text = stringResource(R.string.today_open), onClick = onOpenMeals)
            }
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconTile(background = if (state is TodayMealState.Ordered) SoftMint else SoftGray) {
                    Icon(
                        imageVector = Icons.Default.Restaurant,
                        contentDescription = null,
                        tint = if (state is TodayMealState.Ordered) AccentTeal else MutedText,
                        modifier = Modifier.size(22.dp),
                    )
                }
                Spacer(Modifier.width(13.dp))
                Column(modifier = Modifier.weight(1f)) {
                    val title: String
                    val subtitle: String
                    when (state) {
                        is TodayMealState.Ordered -> {
                            val description = state.meal.description
                                ?.trim()
                                ?.takeIf(String::isNotEmpty)
                            title = description ?: state.meal.title
                            subtitle = state.meal.title
                                .takeIf { description != null && !it.equals(description, ignoreCase = true) }
                                ?: stringResource(R.string.today_meal_ordered)
                        }

                        TodayMealState.NoOrderedMeal -> {
                            title = stringResource(R.string.today_no_meal)
                            subtitle = stringResource(R.string.today_no_meal_subtitle)
                        }

                        TodayMealState.NotConnected -> {
                            title = stringResource(R.string.today_meals_not_connected)
                            subtitle = stringResource(R.string.today_meals_not_connected_subtitle)
                        }
                    }
                    Text(
                        text = title,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = Color.Black,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = subtitle,
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
private fun EmptyDashboardCard() {
    DashboardSurface {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 22.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Verified,
                contentDescription = null,
                tint = MutedText,
                modifier = Modifier.size(30.dp),
            )
            Text(
                text = stringResource(R.string.today_empty_title),
                color = Color.Black,
                fontSize = 17.sp,
                lineHeight = 22.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = stringResource(R.string.today_empty_subtitle),
                color = MutedText,
                fontSize = 13.sp,
                lineHeight = 18.sp,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun NowAndNextCard(
    summary: TodayTimetableSummary,
    onClick: () -> Unit,
) {
    val currentOrNext = summary.currentLesson ?: summary.nextLesson
    val title = when (summary.state) {
        TodayTimetableState.CURRENT -> stringResource(
            R.string.today_lesson_now,
            currentOrNext?.displayTitle().orEmpty(),
        )

        TodayTimetableState.BEFORE_SCHOOL,
        TodayTimetableState.BETWEEN_LESSONS,
        -> stringResource(
            R.string.today_lesson_next,
            currentOrNext?.displayTitle().orEmpty(),
        )

        TodayTimetableState.AFTER_SCHOOL -> stringResource(R.string.today_no_more_lessons)
        TodayTimetableState.WEEKEND -> stringResource(R.string.today_weekend)
        TodayTimetableState.HOLIDAY -> summary.dayDescription ?: stringResource(R.string.today_holiday)
        TodayTimetableState.EMPTY -> stringResource(R.string.today_no_lessons)
        TodayTimetableState.UNAVAILABLE -> stringResource(R.string.today_timetable_unavailable)
    }
    val timingDetail = when (summary.state) {
        TodayTimetableState.CURRENT -> summary.minutesRemainingInCurrent?.let {
            pluralStringResource(R.plurals.today_minutes_remaining, it, it)
        }

        TodayTimetableState.BEFORE_SCHOOL,
        TodayTimetableState.BETWEEN_LESSONS,
        -> summary.minutesUntilNext?.let {
            pluralStringResource(R.plurals.today_starts_in_minutes, it, it)
        }

        else -> null
    }
    val subtitle = when (summary.state) {
        TodayTimetableState.CURRENT,
        TodayTimetableState.BEFORE_SCHOOL,
        TodayTimetableState.BETWEEN_LESSONS,
        -> listOfNotNull(currentOrNext?.details()?.takeIf(String::isNotBlank), timingDetail).joinToString(" · ")

        TodayTimetableState.AFTER_SCHOOL -> stringResource(R.string.today_no_more_lessons_subtitle)
        TodayTimetableState.WEEKEND -> stringResource(R.string.today_weekend_subtitle)
        TodayTimetableState.HOLIDAY -> stringResource(R.string.today_holiday_subtitle)
        TodayTimetableState.EMPTY -> stringResource(R.string.today_no_lessons_subtitle)
        TodayTimetableState.UNAVAILABLE -> stringResource(R.string.today_timetable_unavailable_subtitle)
    }
    val icon: ImageVector = when (summary.state) {
        TodayTimetableState.CURRENT -> Icons.Default.PlayCircle
        TodayTimetableState.BEFORE_SCHOOL,
        TodayTimetableState.BETWEEN_LESSONS,
        -> Icons.Default.Schedule

        TodayTimetableState.AFTER_SCHOOL,
        TodayTimetableState.EMPTY,
        -> Icons.Default.CheckCircle

        TodayTimetableState.WEEKEND,
        TodayTimetableState.HOLIDAY,
        TodayTimetableState.UNAVAILABLE,
        -> Icons.Default.CalendarMonth
    }
    val iconTint = if (summary.state == TodayTimetableState.CURRENT) AccentTeal else MutedText
    val iconBackground = if (summary.state == TodayTimetableState.CURRENT) SoftMint else SoftGray

    DashboardSurface(
        modifier = Modifier.heightIn(min = 96.dp),
        onClick = onClick,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
        ) {
            SectionHeading(stringResource(R.string.today_now_and_next).uppercase(Locale.getDefault()))
            Spacer(Modifier.height(9.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconTile(background = iconBackground, size = 32.dp) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = iconTint,
                        modifier = Modifier.size(20.dp),
                    )
                }
                Spacer(Modifier.width(13.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = title,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = Color.Black,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = subtitle,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = MutedText,
                        fontSize = 13.sp,
                        lineHeight = 17.sp,
                    )
                }
            }
            if (summary.hasChanges) {
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 12.dp),
                    color = Color(0xFFE7E7EA),
                )
                val changedLessons = summary.changedLessons.take(3)
                changedLessons.forEachIndexed { index, lesson ->
                    TimetableChangeRow(lesson)
                    if (index != changedLessons.lastIndex) {
                        Spacer(Modifier.height(10.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun TimetableChangeRow(lesson: ScheduledLesson) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = WarningOrange,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "${lesson.changeKind.localizedLabel()} · ${lesson.displayTitle()}",
                color = Color.Black,
                fontSize = 14.sp,
                lineHeight = 18.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val detail = lesson.changeDescription?.takeIf(String::isNotBlank) ?: lesson.details()
            if (detail.isNotBlank()) {
                Text(
                    text = detail,
                    color = MutedText,
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun LessonChangeKind.localizedLabel(): String = when (this) {
    LessonChangeKind.NONE -> stringResource(R.string.today_timetable_change)
    LessonChangeKind.CANCELED -> stringResource(R.string.today_change_canceled)
    LessonChangeKind.SUBSTITUTION -> stringResource(R.string.today_change_substitution)
    LessonChangeKind.ROOM_CHANGED -> stringResource(R.string.today_change_room)
    LessonChangeKind.ADDED -> stringResource(R.string.today_change_added)
}

@Composable
private fun AbsenceRiskCard(
    rows: List<com.bukovinafilip.gradey.domain.AbsenceSubjectSummary>,
    isThresholdUnavailable: Boolean,
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
                SectionHeading(stringResource(R.string.today_absence_risk).uppercase(Locale.getDefault()))
                ActionPill(text = stringResource(R.string.today_open), onClick = onOpenAbsence)
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
                    Text(
                        text = stringResource(R.string.today_absence_unavailable),
                        color = MutedText,
                        fontSize = 14.sp,
                    )
                }
            } else {
                rows.forEach { row ->
                    val color = row.level.riskColor()
                    RiskRow(
                        subjectName = row.subjectName,
                        missedLessons = row.base,
                        totalLessons = row.lessonsCount,
                        percentage = row.absencePercentage,
                        threshold = row.threshold,
                        missesUntilLimit = row.missesUntilLimit,
                        color = color,
                    )
                }
                if (isThresholdUnavailable) {
                    Text(
                        text = stringResource(R.string.today_school_limit_unavailable),
                        modifier = Modifier.padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 6.dp),
                        color = MutedText,
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun RiskRow(
    subjectName: String,
    missedLessons: Int,
    totalLessons: Int,
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
                text = absenceLimitDescription(missedLessons, totalLessons, missesUntilLimit),
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
private fun NewMarksAndTrendsCard(
    newMarks: List<TodayNewMark>,
    trends: List<SubjectGradeTrend>,
    onOpenMarks: () -> Unit,
    onOpenTrends: () -> Unit,
) {
    DashboardSurface {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 15.dp, bottom = 10.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                SectionHeading(
                    stringResource(R.string.today_new_marks_and_trends).uppercase(Locale.getDefault()),
                )
                ActionPill(text = stringResource(R.string.today_view_all), onClick = onOpenTrends)
            }
            Spacer(Modifier.height(6.dp))
            newMarks.forEachIndexed { index, mark ->
                if (index > 0) {
                    HorizontalDivider(
                        modifier = Modifier.padding(start = 67.dp, end = 16.dp),
                        color = SoftGray,
                    )
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onOpenMarks)
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconTile(background = SoftMint) {
                        Icon(
                            imageVector = Icons.Default.Verified,
                            contentDescription = null,
                            tint = AccentTeal,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    Spacer(Modifier.width(13.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = stringResource(
                                R.string.today_mark_in_subject,
                                mark.markText,
                                mark.subjectName,
                            ),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = Color.Black,
                            fontSize = 16.sp,
                            lineHeight = 20.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = mark.detectedAt?.let(::formatDetectedAt)
                                ?: stringResource(R.string.today_new_from_school),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = MutedText,
                            fontSize = 13.sp,
                            lineHeight = 17.sp,
                        )
                    }
                }
            }
            if (newMarks.isNotEmpty() && trends.isNotEmpty()) {
                HorizontalDivider(
                    modifier = Modifier.padding(start = 67.dp, end = 16.dp),
                    color = SoftGray,
                )
            }
            if (trends.isEmpty()) {
                CloudHistoryEmptyRow()
            } else {
                trends.forEachIndexed { index, trend ->
                    if (index > 0) {
                        HorizontalDivider(
                            modifier = Modifier.padding(start = 67.dp, end = 16.dp),
                            color = SoftGray,
                        )
                    }
                    GradeTrendRow(trend)
                }
            }
        }
    }
}

@Composable
private fun GradeTrendsScreen(
    trends: List<SubjectGradeTrend>,
    selectedRangeName: String,
    onRangeSelected: (GradeTrendRange) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val selectedRange = runCatching { GradeTrendRange.valueOf(selectedRangeName) }
        .getOrDefault(GradeTrendRange.NINETY_DAYS)
    val filteredTrends = remember(trends, selectedRange) {
        GradeHistoryTrends.inRange(trends, selectedRange)
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(BackgroundTop, BackgroundMiddle, BackgroundBottom))),
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, top = 18.dp, end = 16.dp, bottom = 126.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item { GradeTrendsHeader(onBack) }
            item {
                GradeTrendRangePicker(
                    selected = selectedRange,
                    onSelected = onRangeSelected,
                )
            }
            item {
                if (filteredTrends.isEmpty()) {
                    GradeTrendsEmptyCard()
                } else {
                    GradeTrendsList(filteredTrends)
                }
            }
        }
    }
}

@Composable
private fun GradeTrendsHeader(onBack: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(42.dp),
            onClick = onBack,
            shape = CircleShape,
            color = Color.White.copy(alpha = 0.82f),
            shadowElevation = 1.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Default.ChevronLeft,
                    contentDescription = stringResource(R.string.today_back),
                    tint = AccentTeal,
                    modifier = Modifier.size(28.dp),
                )
            }
        }
        Text(
            text = stringResource(R.string.today_grade_movement),
            color = Color.Black,
            fontSize = 18.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun GradeTrendRangePicker(
    selected: GradeTrendRange,
    onSelected: (GradeTrendRange) -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(38.dp),
        shape = RoundedCornerShape(20.dp),
        color = Color(0xFFD7E4E4).copy(alpha = 0.92f),
    ) {
        Row(modifier = Modifier.padding(2.dp)) {
            GradeTrendRange.entries.forEach { range ->
                Surface(
                    modifier = Modifier
                        .weight(1f)
                        .height(34.dp),
                    onClick = { onSelected(range) },
                    shape = RoundedCornerShape(18.dp),
                    color = if (range == selected) Color.White else Color.Transparent,
                    shadowElevation = if (range == selected) 1.dp else 0.dp,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            text = trendRangeLabel(range),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = Color.Black,
                            fontSize = 13.sp,
                            lineHeight = 16.sp,
                            fontWeight = if (range == selected) FontWeight.Bold else FontWeight.Normal,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun trendRangeLabel(range: GradeTrendRange): String = stringResource(
    when (range) {
        GradeTrendRange.THIRTY_DAYS -> R.string.today_range_30
        GradeTrendRange.NINETY_DAYS -> R.string.today_range_90
        GradeTrendRange.SCHOOL_YEAR -> R.string.today_school_year
    },
)

@Composable
private fun GradeTrendsList(trends: List<SubjectGradeTrend>) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        color = CardWhite,
        shadowElevation = 2.dp,
    ) {
        Column {
            trends.forEachIndexed { index, trend ->
                GradeTrendRow(trend)
                if (index != trends.lastIndex) {
                    HorizontalDivider(
                        modifier = Modifier.padding(start = 106.dp, end = 16.dp),
                        color = SoftGray,
                    )
                }
            }
        }
    }
}

@Composable
private fun GradeTrendsEmptyCard() {
    DashboardSurface {
        Column(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = MutedText,
                modifier = Modifier.size(28.dp),
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.today_no_grade_history),
                color = Color.Black,
                fontSize = 16.sp,
                lineHeight = 20.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text = stringResource(R.string.today_cloud_trends_subtitle),
                color = MutedText,
                fontSize = 13.sp,
                lineHeight = 17.sp,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun CloudHistoryEmptyRow() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconTile(background = SoftGray) {
            Icon(
                imageVector = Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = MutedText,
                modifier = Modifier.size(21.dp),
            )
        }
        Spacer(Modifier.width(13.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = stringResource(R.string.today_no_grade_history),
                color = Color.Black,
                fontSize = 15.sp,
                lineHeight = 19.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = stringResource(R.string.today_cloud_trends_subtitle),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = MutedText,
                fontSize = 12.sp,
                lineHeight = 16.sp,
            )
        }
    }
}

@Composable
private fun GradeTrendRow(trend: SubjectGradeTrend) {
    val newMarkCount = (trend.latestMarkCount - trend.firstMarkCount).coerceAtLeast(0)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(62.dp)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            modifier = Modifier
                .width(76.dp)
                .height(34.dp),
            shape = RoundedCornerShape(10.dp),
            color = SoftMint,
        ) {
            GradeTrendSparkline(trend.events.mapNotNull { it.averageValue })
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = trend.displayName,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = Color.Black,
                fontSize = 15.sp,
                lineHeight = 18.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = if (newMarkCount > 0) {
                    pluralStringResource(R.plurals.today_trend_new_marks, newMarkCount, newMarkCount)
                } else {
                    stringResource(R.string.today_average_movement)
                },
                color = MutedText,
                fontSize = 12.sp,
                lineHeight = 15.sp,
            )
        }
        trend.averageDelta?.let { delta ->
            Text(
                text = String.format(Locale.getDefault(), "%+.2f", delta),
                color = if (delta <= 0) AccentTeal else DangerRed,
                fontSize = 15.sp,
                lineHeight = 18.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun GradeTrendSparkline(values: List<Double>) {
    Canvas(modifier = Modifier.fillMaxSize().padding(horizontal = 6.dp, vertical = 7.dp)) {
        if (values.isEmpty()) return@Canvas
        val minimum = values.minOrNull() ?: return@Canvas
        val maximum = values.maxOrNull() ?: return@Canvas
        val range = (maximum - minimum).takeIf { it > 0.001 } ?: 1.0
        val offsets = values.mapIndexed { index, value ->
            val x = if (values.size == 1) size.width / 2f else size.width * index / values.lastIndex.toFloat()
            val y = size.height - size.height * ((value - minimum) / range).toFloat()
            Offset(x, y)
        }
        if (offsets.size > 1) {
            val path = Path().apply {
                moveTo(offsets.first().x, offsets.first().y)
                offsets.drop(1).forEach { lineTo(it.x, it.y) }
            }
            drawPath(
                path = path,
                color = AccentTeal,
                style = Stroke(width = 2.2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
            )
        }
        offsets.forEach { drawCircle(AccentTeal, radius = 2.dp.toPx(), center = it) }
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

private fun formatDetectedAt(instant: java.time.Instant): String =
    DateTimeFormatter
        .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .withZone(PragueZone)
        .format(instant)

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

@Composable
private fun absenceLimitDescription(
    missedLessons: Int,
    totalLessons: Int,
    missesUntilLimit: Int?,
): String = when (missesUntilLimit) {
    null -> stringResource(R.string.today_absence_missed, missedLessons, totalLessons)
    0 -> stringResource(R.string.today_absence_over_limit)
    else -> stringResource(R.string.today_absence_until_limit, missesUntilLimit)
}

private fun plural(count: Int, singular: String, plural: String): String =
    if (count == 1) singular else plural
