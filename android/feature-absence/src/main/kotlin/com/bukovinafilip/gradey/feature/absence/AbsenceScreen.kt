package com.bukovinafilip.gradey.feature.absence

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.domain.AbsenceDaySummary
import com.bukovinafilip.gradey.domain.AbsenceLessonCandidate
import com.bukovinafilip.gradey.domain.AbsenceMonthSummary
import com.bukovinafilip.gradey.domain.AbsenceManualSelectionPolicy
import com.bukovinafilip.gradey.domain.AbsencePartialDayCandidate
import com.bukovinafilip.gradey.ui.GradeyIcons
import com.bukovinafilip.gradey.ui.StatusChip
import com.bukovinafilip.gradey.domain.AbsencePrediction
import com.bukovinafilip.gradey.domain.AbsencePredictionResult
import com.bukovinafilip.gradey.domain.AbsencePredictionSubjectRow
import com.bukovinafilip.gradey.domain.AbsencePresentationState
import com.bukovinafilip.gradey.domain.AbsenceRiskLevel
import com.bukovinafilip.gradey.domain.AbsenceRiskSummary
import com.bukovinafilip.gradey.domain.AbsenceSubjectResolutionProgress
import com.bukovinafilip.gradey.domain.AbsenceSubjectSummary
import com.bukovinafilip.gradey.domain.AbsenceTimeline
import com.bukovinafilip.gradey.domain.AbsenceTimelineSummary
import com.bukovinafilip.gradey.domain.TimetableDates
import com.bukovinafilip.gradey.model.AbsenceCounts
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.ui.GradeyAuroraBackground
import com.bukovinafilip.gradey.ui.GradeyColors
import java.time.format.FormatStyle
import java.time.format.DateTimeFormatter
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlin.math.ceil
import kotlin.math.max

private val RiskOrange = Color(0xFFFF8D28)
private val LateOrange = Color(0xFFD98F10)
private val MissedRed = Color(0xFFD95461)
private val RiskWatchOrange = Color(0xFFFF9500)

private enum class AbsenceMode {
    Subjects,
    Days,
    Months,
}

@Composable
fun AbsenceStateScreen(
    state: AbsencePresentationState,
    errorMessage: String?,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentAlignment = Alignment.Center,
    ) {
        GradeyAuroraBackground()
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = stringResource(R.string.absence_title),
                color = MaterialTheme.colorScheme.onBackground,
                fontSize = 30.sp,
                lineHeight = 36.sp,
                fontWeight = FontWeight.Bold,
            )
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surfaceContainer,
                shadowElevation = 2.dp,
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 28.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (state == AbsencePresentationState.INITIAL_LOADING) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                        Text(
                            text = stringResource(R.string.absence_loading),
                            color = MaterialTheme.colorScheme.onSurface,
                            fontSize = 18.sp,
                            lineHeight = 23.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = stringResource(R.string.absence_loading_subtitle),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    } else {
                        Icon(
                            imageVector = GradeyIcons.ErrorCircle,
                            contentDescription = null,
                            tint = RiskOrange,
                            modifier = Modifier.size(34.dp),
                        )
                        Text(
                            text = stringResource(R.string.absence_load_failed),
                            color = MaterialTheme.colorScheme.onSurface,
                            fontSize = 18.sp,
                            lineHeight = 23.sp,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            text = errorMessage ?: stringResource(R.string.absence_load_failed_subtitle),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                        Button(onClick = onRetry) {
                            Text(stringResource(R.string.absence_retry))
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun AbsenceScreen(
    response: AbsenceResponse,
    studentName: String,
    isRefreshing: Boolean,
    isResolvingSubjects: Boolean,
    subjectResolutionProgress: AbsenceSubjectResolutionProgress?,
    subjectResolutionWarning: String?,
    subjectResolutionError: String?,
    unresolvedPartialDays: List<AbsencePartialDayCandidate>,
    onRefresh: () -> Unit,
    onRetrySubjectResolution: () -> Unit,
    onSaveManualSelections: suspend (Map<String, Set<String>>) -> String?,
    predictorScopeKey: String,
    onLoadPredictionLessons: suspend (String) -> List<AbsenceLessonCandidate>,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var mode by rememberSaveable { mutableStateOf(AbsenceMode.Subjects) }
    var isManualSheetPresented by rememberSaveable { mutableStateOf(false) }
    var manualDrafts by remember { mutableStateOf<Map<String, Set<String>>>(emptyMap()) }
    var manualSelectionError by remember { mutableStateOf<String?>(null) }
    var isSavingManualSelections by remember { mutableStateOf(false) }
    var isPredictionSheetPresented by rememberSaveable(predictorScopeKey) { mutableStateOf(false) }
    var predictionSelectedDate by remember(predictorScopeKey) { mutableStateOf(TimetableDates.today()) }
    var predictionSelectedLessons by remember(predictorScopeKey) {
        mutableStateOf<List<AbsenceLessonCandidate>>(emptyList())
    }
    val scope = rememberCoroutineScope()
    val locale = LocalConfiguration.current.locales[0]
    val timeline = remember(response) { AbsenceTimeline.make(response) }
    val riskSummary = remember(response) {
        AbsenceRiskSummary.make(response, response.absencesPerSubject)
    }
    val predictionResult = remember(timeline.total, riskSummary.subjects, predictionSelectedLessons, response.percentageThreshold) {
        AbsencePrediction.project(
            currentTotalCounts = timeline.total,
            subjectRows = riskSummary.subjects,
            selectedLessons = predictionSelectedLessons,
            threshold = response.percentageThreshold,
        )
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        GradeyAuroraBackground()
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
                    locale = locale,
                )
            }
            item { Spacer(Modifier.height(11.dp)) }
            item {
                AbsencePredictorCard(
                    result = predictionResult,
                    locale = locale,
                    onOpen = { isPredictionSheetPresented = true },
                    onClear = { predictionSelectedLessons = emptyList() },
                )
            }
            item { Spacer(Modifier.height(11.dp)) }
            item { AbsenceModePicker(selected = mode, onSelect = { mode = it }) }
            when (mode) {
                AbsenceMode.Subjects -> {
                    item { Spacer(Modifier.height(12.dp)) }
                    item {
                        SubjectsCard(
                            subjects = riskSummary.subjects,
                            locale = locale,
                            isResolving = isResolvingSubjects,
                            progress = subjectResolutionProgress,
                            warning = subjectResolutionWarning,
                            error = subjectResolutionError,
                            unresolvedPartialDays = unresolvedPartialDays,
                            onRetry = onRetrySubjectResolution,
                            onChooseLessons = {
                                manualDrafts = unresolvedPartialDays.associate { day ->
                                    day.dateKey to day.selectedLessonIDs.toSet()
                                }
                                manualSelectionError = null
                                isManualSheetPresented = true
                            },
                        )
                    }
                }

                AbsenceMode.Days -> {
                    item { Spacer(Modifier.height(12.dp)) }
                    item { DaysCard(timeline, locale) }
                }

                AbsenceMode.Months -> {
                    if (timeline.months.size >= 2) {
                        item { Spacer(Modifier.height(8.dp)) }
                        item { SectionHeading(stringResource(R.string.absence_months_chart).uppercase(locale)) }
                        item { Spacer(Modifier.height(8.dp)) }
                        item { MonthsChartCard(timeline.months, locale) }
                        item { Spacer(Modifier.height(9.dp)) }
                    } else {
                        item { Spacer(Modifier.height(12.dp)) }
                    }
                    item { MonthsCard(timeline, locale) }
                }
            }
        }
    }

    if (isManualSheetPresented) {
        ManualAbsenceLessonSelectionSheet(
            days = unresolvedPartialDays,
            drafts = manualDrafts,
            locale = locale,
            errorMessage = manualSelectionError,
            isSaving = isSavingManualSelections,
            onToggle = { dateKey, lessonID ->
                val day = unresolvedPartialDays.firstOrNull { it.dateKey == dateKey }
                    ?: return@ManualAbsenceLessonSelectionSheet
                val selected = AbsenceManualSelectionPolicy.toggle(
                    current = manualDrafts[dateKey].orEmpty(),
                    lessonID = lessonID,
                    requiredSelectionCount = day.requiredSelectionCount,
                )
                manualDrafts = manualDrafts + (dateKey to selected)
            },
            onDismiss = {
                if (!isSavingManualSelections) {
                    manualSelectionError = null
                    isManualSheetPresented = false
                }
            },
            onSave = {
                scope.launch {
                    isSavingManualSelections = true
                    manualSelectionError = try {
                        onSaveManualSelections(manualDrafts)
                    } finally {
                        isSavingManualSelections = false
                    }
                    if (manualSelectionError == null) {
                        manualDrafts = emptyMap()
                        isManualSheetPresented = false
                    }
                }
            },
        )
    }

    if (isPredictionSheetPresented) {
        AbsencePredictionSheet(
            initialDate = predictionSelectedDate,
            minimumDate = TimetableDates.today(),
            initialSelectedLessons = predictionSelectedLessons,
            locale = locale,
            onLoadLessons = onLoadPredictionLessons,
            onDismiss = { isPredictionSheetPresented = false },
            onDone = { selectedDate, lessons ->
                predictionSelectedDate = selectedDate
                predictionSelectedLessons = lessons
                isPredictionSheetPresented = false
            },
        )
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
            color = MaterialTheme.colorScheme.surfaceContainer,
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
                            contentDescription = stringResource(R.string.absence_open_gradey_tools),
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            }
        }

        Text(
            text = stringResource(R.string.absence_title),
            color = MaterialTheme.colorScheme.onBackground,
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
            color = MaterialTheme.colorScheme.surfaceContainer,
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
                                color = MaterialTheme.colorScheme.primary,
                                strokeWidth = 2.5.dp,
                            )
                        } else {
                            Icon(
                                imageVector = GradeyIcons.Refresh,
                                contentDescription = stringResource(R.string.absence_refresh),
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(27.dp),
                            )
                        }
                    }
                }
                Surface(
                    modifier = Modifier.size(32.dp),
                    onClick = onOpenAccount,
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = GradeyIcons.User,
                            contentDescription = stringResource(R.string.absence_open_account),
                            tint = MaterialTheme.colorScheme.primary,
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
    locale: java.util.Locale,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 140.dp),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
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
                        text = stringResource(R.string.absence_title),
                        color = MaterialTheme.colorScheme.onSurface,
                        fontSize = 17.sp,
                        lineHeight = 21.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = studentName.ifBlank { stringResource(R.string.absence_student) },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 17.sp,
                        lineHeight = 20.sp,
                    )
                }
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = counts.total.toString(),
                        color = MaterialTheme.colorScheme.primary,
                        fontSize = 24.sp,
                        lineHeight = 28.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = stringResource(R.string.absence_total_hours),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                text = threshold?.let {
                    stringResource(R.string.absence_school_limit, formatWhole(it, locale))
                } ?: stringResource(R.string.absence_school_limit_unavailable),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
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
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                imageVector = GradeyIcons.Calendar,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(25.dp),
            )
            Icon(
                imageVector = GradeyIcons.ErrorCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 8.dp, bottom = 8.dp)
                    .size(11.dp),
            )
        }
    }
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
private fun SummaryPills(counts: AbsenceCounts) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        AttendanceKind.entries
            .filter { it.value(counts) > 0 }
            .forEach { kind -> CountPill(kind, kind.value(counts)) }
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
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f),
    ) {
        Row(modifier = Modifier.padding(2.dp)) {
            AbsenceMode.entries.forEach { mode ->
                val label = mode.localizedLabel()
                Surface(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxSize()
                        .selectable(
                            selected = selected == mode,
                            role = Role.Tab,
                            onClick = { onSelect(mode) },
                        )
                        .semantics { contentDescription = label },
                    shape = RoundedCornerShape(15.dp),
                    color = if (selected == mode) {
                        MaterialTheme.colorScheme.surfaceContainerHigh
                    } else {
                        Color.Transparent
                    },
                    shadowElevation = if (selected == mode) 1.dp else 0.dp,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            text = label,
                            color = MaterialTheme.colorScheme.onSurface,
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
private fun AbsenceMode.localizedLabel(): String = when (this) {
    AbsenceMode.Subjects -> stringResource(R.string.absence_segment_subjects)
    AbsenceMode.Days -> stringResource(R.string.absence_segment_days)
    AbsenceMode.Months -> stringResource(R.string.absence_segment_months)
}

@Composable
private fun SubjectsCard(
    subjects: List<AbsenceSubjectSummary>,
    locale: java.util.Locale,
    isResolving: Boolean,
    progress: AbsenceSubjectResolutionProgress?,
    warning: String?,
    error: String?,
    unresolvedPartialDays: List<AbsencePartialDayCandidate>,
    onRetry: () -> Unit,
    onChooseLessons: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (!warning.isNullOrBlank()) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surfaceContainer,
                shadowElevation = 1.dp,
            ) {
                Row(
                    modifier = Modifier.padding(14.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(GradeyIcons.ErrorCircle, contentDescription = null, tint = LateOrange)
                    Text(warning, color = LateOrange, fontSize = 14.sp, lineHeight = 19.sp)
                }
            }
        }
        if (!isResolving && error.isNullOrBlank() && unresolvedPartialDays.isNotEmpty()) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surfaceContainer,
                shadowElevation = 1.dp,
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        stringResource(R.string.absence_manual_callout_title),
                        color = MaterialTheme.colorScheme.primary,
                        fontSize = 15.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        stringResource(R.string.absence_manual_callout_message, unresolvedPartialDays.size),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 14.sp,
                        lineHeight = 19.sp,
                    )
                    Button(onClick = onChooseLessons) {
                        Text(stringResource(R.string.absence_manual_callout_button))
                    }
                }
            }
        }
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(20.dp),
            color = MaterialTheme.colorScheme.surfaceContainer,
            shadowElevation = 1.dp,
        ) {
            when {
                isResolving -> Row(
                    modifier = Modifier.padding(18.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = MaterialTheme.colorScheme.primary,
                        strokeWidth = 2.dp,
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            stringResource(R.string.absence_subjects_calculating),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 14.sp,
                            lineHeight = 19.sp,
                        )
                        if (progress != null) {
                            Text(
                                stringResource(
                                    R.string.absence_subjects_progress,
                                    progress.completedWeeks,
                                    progress.totalWeeks,
                                ),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 12.sp,
                                lineHeight = 16.sp,
                            )
                        }
                    }
                }

                !error.isNullOrBlank() -> Column(
                    modifier = Modifier.padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        stringResource(R.string.absence_subjects_error_title),
                        color = MissedRed,
                        fontSize = 16.sp,
                        lineHeight = 21.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        error,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 14.sp,
                        lineHeight = 19.sp,
                    )
                    Button(onClick = onRetry) {
                        Text(stringResource(R.string.absence_retry))
                    }
                }

                subjects.isEmpty() -> EmptyState(stringResource(R.string.absence_subjects_empty))
                else -> Column {
                    subjects.forEachIndexed { index, subject ->
                        SubjectRow(subject, locale)
                        if (index != subjects.lastIndex) {
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outlineVariant,
                                thickness = 0.33.dp,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AbsencePredictorCard(
    result: AbsencePredictionResult,
    locale: java.util.Locale,
    onOpen: () -> Unit,
    onClear: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    stringResource(R.string.absence_predictor_title),
                    modifier = Modifier.weight(1f),
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = 17.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.Bold,
                )
                if (result.hasSelection) {
                    TextButton(onClick = onClear) {
                        Text(stringResource(R.string.absence_predictor_clear))
                    }
                }
                Button(onClick = onOpen) {
                    Text(
                        stringResource(
                            if (result.hasSelection) R.string.absence_predictor_edit else R.string.absence_predictor_open,
                        ),
                    )
                }
            }

            if (!result.hasSelection) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        stringResource(R.string.absence_predictor_empty_title),
                        color = MaterialTheme.colorScheme.onSurface,
                        fontSize = 15.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        stringResource(R.string.absence_predictor_empty_message),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 14.sp,
                        lineHeight = 19.sp,
                    )
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            stringResource(R.string.absence_predictor_total),
                            color = MaterialTheme.colorScheme.onSurface,
                            fontSize = 15.sp,
                            lineHeight = 20.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            stringResource(R.string.absence_predictor_added, result.addedHours),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 13.sp,
                            lineHeight = 17.sp,
                        )
                    }
                    Text(
                        "${result.currentTotal.total} → ${result.projectedTotal.total}",
                        color = MaterialTheme.colorScheme.primary,
                        fontSize = 19.sp,
                        lineHeight = 24.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
                if (result.subjectRows.isNotEmpty()) {
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outlineVariant,
                        thickness = 0.33.dp,
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        result.subjectRows.forEach { row ->
                            AbsencePredictionSubjectRow(row, locale)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AbsencePredictionSubjectRow(
    row: AbsencePredictionSubjectRow,
    locale: java.util.Locale,
) {
    val warningColor = if (row.exceedsThreshold) MissedRed else MaterialTheme.colorScheme.primary
    val currentBase = row.currentBase
    val projectedBase = row.projectedBase
    val currentPercentage = row.currentPercentage
    val projectedPercentage = row.projectedPercentage
    val detail = if (
        currentBase == null || projectedBase == null ||
        currentPercentage == null || projectedPercentage == null
    ) {
        stringResource(R.string.absence_predictor_baseline_unavailable)
    } else {
        stringResource(
            R.string.absence_predictor_subject_change,
            currentBase,
            projectedBase,
            formatOneDecimal(currentPercentage, locale),
            formatOneDecimal(projectedPercentage, locale),
        )
    }
    val status = when {
        row.crossesThreshold -> stringResource(R.string.absence_predictor_crosses_limit)
        row.exceedsThreshold -> stringResource(R.string.absence_predictor_over_limit)
        else -> stringResource(R.string.absence_predictor_added, row.addedHours)
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                row.subjectName,
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 15.sp,
                lineHeight = 20.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(detail, color = warningColor, fontSize = 13.sp, lineHeight = 18.sp)
        }
        StatusChip(text = status, color = warningColor)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AbsencePredictionSheet(
    initialDate: LocalDate,
    minimumDate: LocalDate,
    initialSelectedLessons: List<AbsenceLessonCandidate>,
    locale: java.util.Locale,
    onLoadLessons: suspend (String) -> List<AbsenceLessonCandidate>,
    onDismiss: () -> Unit,
    onDone: (LocalDate, List<AbsenceLessonCandidate>) -> Unit,
) {
    var selectedDate by remember { mutableStateOf(maxOf(initialDate, minimumDate)) }
    var lessons by remember { mutableStateOf<List<AbsenceLessonCandidate>>(emptyList()) }
    var lessonsByDate by remember { mutableStateOf<Map<String, List<AbsenceLessonCandidate>>>(emptyMap()) }
    var lessonCacheByID by remember(initialSelectedLessons) {
        mutableStateOf(initialSelectedLessons.associateBy(AbsenceLessonCandidate::id))
    }
    var draftLessonIDs by remember(initialSelectedLessons) {
        mutableStateOf<Set<String>>(initialSelectedLessons.mapTo(mutableSetOf(), AbsenceLessonCandidate::id))
    }
    var isLoading by remember { mutableStateOf(false) }
    var hasLoadError by remember { mutableStateOf(false) }
    var retryAttempt by remember { mutableStateOf(0) }
    val dateFormatter = remember(locale) {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)
    }
    LaunchedEffect(selectedDate, retryAttempt) {
        val dateKey = TimetableDates.apiDateString(selectedDate)
        lessonsByDate[dateKey]?.let { cached ->
            lessons = cached
            hasLoadError = false
            isLoading = false
            return@LaunchedEffect
        }
        isLoading = true
        hasLoadError = false
        lessons = emptyList()
        try {
            val loaded = onLoadLessons(dateKey)
            if (selectedDate != LocalDate.parse(dateKey)) return@LaunchedEffect
            lessonsByDate = lessonsByDate + (dateKey to loaded)
            lessonCacheByID = lessonCacheByID + loaded.associateBy(AbsenceLessonCandidate::id)
            lessons = loaded
            isLoading = false
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            hasLoadError = true
            lessons = emptyList()
            isLoading = false
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 18.dp, end = 18.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(R.string.absence_predictor_sheet_title),
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 21.sp,
                lineHeight = 26.sp,
                fontWeight = FontWeight.Bold,
            )
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TextButton(
                        enabled = selectedDate > minimumDate,
                        onClick = { selectedDate = selectedDate.minusDays(1) },
                    ) {
                        Text(stringResource(R.string.absence_predictor_previous_day))
                    }
                    Text(
                        selectedDate.format(dateFormatter),
                        modifier = Modifier.weight(1f),
                        color = MaterialTheme.colorScheme.onSurface,
                        textAlign = TextAlign.Center,
                        fontSize = 15.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    TextButton(onClick = { selectedDate = selectedDate.plusDays(1) }) {
                        Text(stringResource(R.string.absence_predictor_next_day))
                    }
                }
            }

            Text(
                stringResource(R.string.absence_predictor_selected_count, draftLessonIDs.size),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp,
                lineHeight = 17.sp,
            )

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 480.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                when {
                    isLoading -> item {
                        Row(
                            modifier = Modifier.padding(vertical = 14.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator(modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
                            Text(
                                stringResource(R.string.absence_predictor_loading),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    hasLoadError -> item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                stringResource(R.string.absence_predictor_load_failed),
                                color = MissedRed,
                                fontSize = 14.sp,
                                lineHeight = 19.sp,
                            )
                            Button(onClick = { retryAttempt += 1 }) {
                                Text(stringResource(R.string.absence_retry))
                            }
                        }
                    }

                    lessons.isEmpty() -> item {
                        Text(
                            stringResource(R.string.absence_predictor_no_lessons),
                            modifier = Modifier.padding(vertical = 14.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 14.sp,
                            lineHeight = 19.sp,
                        )
                    }

                    else -> lessons.forEach { lesson ->
                        item(key = lesson.id) {
                            val isSelected = lesson.id in draftLessonIDs
                            Surface(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        draftLessonIDs = draftLessonIDs.toMutableSet().apply {
                                            if (!remove(lesson.id)) add(lesson.id)
                                        }
                                    },
                                shape = RoundedCornerShape(14.dp),
                                color = if (isSelected) {
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)
                                } else {
                                    MaterialTheme.colorScheme.surfaceContainerHigh
                                },
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 11.dp),
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            "${lesson.hourCaption}. ${lesson.subjectName}",
                                            color = MaterialTheme.colorScheme.onSurface,
                                            fontSize = 15.sp,
                                            lineHeight = 20.sp,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                        if (lesson.timeRange.isNotBlank()) {
                                            Text(
                                                lesson.timeRange,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                fontSize = 13.sp,
                                                lineHeight = 17.sp,
                                            )
                                        }
                                    }
                                    Icon(
                                        GradeyIcons.Tick,
                                        contentDescription = if (isSelected) {
                                            stringResource(R.string.absence_predictor_selected)
                                        } else {
                                            null
                                        },
                                        tint = if (isSelected) {
                                            MaterialTheme.colorScheme.primary
                                        } else {
                                            Color.Transparent
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }

            TextButton(
                enabled = draftLessonIDs.isNotEmpty(),
                onClick = { draftLessonIDs = emptySet() },
            ) {
                Text(stringResource(R.string.absence_predictor_clear))
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.absence_manual_cancel))
                }
                Button(
                    onClick = {
                        onDone(
                            selectedDate,
                            AbsencePrediction.selectedLessonsByID(
                                draftLessonIDs.mapNotNull(lessonCacheByID::get),
                            ),
                        )
                    },
                ) {
                    Text(stringResource(R.string.absence_predictor_done))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ManualAbsenceLessonSelectionSheet(
    days: List<AbsencePartialDayCandidate>,
    drafts: Map<String, Set<String>>,
    locale: java.util.Locale,
    errorMessage: String?,
    isSaving: Boolean,
    onToggle: (dateKey: String, lessonID: String) -> Unit,
    onDismiss: () -> Unit,
    onSave: () -> Unit,
) {
    val canSave = AbsenceManualSelectionPolicy.canSave(days, drafts)
    val dateFormatter = remember(locale) { DateTimeFormatter.ofPattern("EEE d. M.", locale) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 18.dp, end = 18.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(R.string.absence_manual_title),
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 21.sp,
                lineHeight = 26.sp,
                fontWeight = FontWeight.Bold,
            )
            if (!errorMessage.isNullOrBlank()) {
                Text(errorMessage, color = MissedRed, fontSize = 14.sp, lineHeight = 19.sp)
            }
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 520.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                days.forEach { day ->
                    item(key = "header-${day.dateKey}") {
                        val dateLabel = runCatching { LocalDate.parse(day.dateKey).format(dateFormatter) }
                            .getOrDefault(day.dateKey)
                        Column(modifier = Modifier.padding(top = 6.dp)) {
                            Text(
                                dateLabel,
                                color = MaterialTheme.colorScheme.onSurface,
                                fontSize = 16.sp,
                                lineHeight = 21.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                stringResource(
                                    R.string.absence_manual_selected_count,
                                    drafts[day.dateKey].orEmpty().size,
                                    day.requiredSelectionCount,
                                ),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 13.sp,
                                lineHeight = 17.sp,
                            )
                        }
                    }
                    day.lessons.forEach { lesson ->
                        item(key = lesson.id) {
                            val isSelected = lesson.id in drafts[day.dateKey].orEmpty()
                            Surface(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable(enabled = !isSaving) {
                                        onToggle(day.dateKey, lesson.id)
                                    },
                                shape = RoundedCornerShape(14.dp),
                                color = if (isSelected) {
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)
                                } else {
                                    MaterialTheme.colorScheme.surfaceContainerHigh
                                },
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 11.dp),
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            "${lesson.hourCaption}. ${lesson.subjectName}",
                                            color = MaterialTheme.colorScheme.onSurface,
                                            fontSize = 15.sp,
                                            lineHeight = 20.sp,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                        if (lesson.timeRange.isNotBlank()) {
                                            Text(
                                                lesson.timeRange,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                fontSize = 13.sp,
                                                lineHeight = 17.sp,
                                            )
                                        }
                                    }
                                    Text(
                                        if (isSelected) "✓" else "○",
                                        color = if (isSelected) {
                                            MaterialTheme.colorScheme.primary
                                        } else {
                                            MaterialTheme.colorScheme.onSurfaceVariant
                                        },
                                        fontSize = 22.sp,
                                        lineHeight = 24.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                }
                            }
                        }
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(enabled = !isSaving, onClick = onDismiss) {
                    Text(stringResource(R.string.absence_manual_cancel))
                }
                Button(enabled = canSave && !isSaving, onClick = onSave) {
                    if (isSaving) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            color = MaterialTheme.colorScheme.onPrimary,
                            strokeWidth = 2.dp,
                        )
                    } else {
                        Text(stringResource(R.string.absence_manual_save))
                    }
                }
            }
        }
    }
}

@Composable
private fun SubjectRow(subject: AbsenceSubjectSummary, locale: java.util.Locale) {
    val color = subject.level.riskColor()
    val missedLabel = stringResource(R.string.absence_subject_missed, subject.base, subject.lessonsCount)
    val limitLabel = subject.missesUntilLimit?.let {
        stringResource(R.string.absence_more_until_limit, it)
    } ?: stringResource(R.string.absence_limit_unavailable)
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
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 17.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "${formatOneDecimal(subject.absencePercentage, locale)} %",
                color = color,
                fontSize = 17.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Spacer(Modifier.height(5.dp))
        RiskCapsuleBar(
            percentage = subject.absencePercentage,
            threshold = subject.threshold,
            color = color,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = buildAnnotatedString {
                append(missedLabel)
                append(" ")
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                    append(limitLabel)
                }
            },
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
            lineHeight = 16.sp,
            maxLines = 1,
        )
    }
}

@Composable
private fun RiskCapsuleBar(
    percentage: Double,
    threshold: Double?,
    color: Color,
) {
    val fraction = (
        if (threshold != null && threshold > 0.0) {
            percentage / threshold
        } else {
            percentage / 100.0
        }
    ).coerceIn(0.0, 1.0).toFloat()
    val fillColor = if (threshold == null) {
        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
    } else {
        color
    }
    val railColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.12f)

    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(6.dp),
    ) {
        val cornerRadius = CornerRadius(size.height / 2f)
        drawRoundRect(
            color = railColor,
            size = size,
            cornerRadius = cornerRadius,
        )
        if (fraction > 0f) {
            val fillWidth = max(size.width * fraction, minOf(6.dp.toPx(), size.width))
            drawRoundRect(
                color = fillColor,
                size = Size(fillWidth, size.height),
                cornerRadius = cornerRadius,
            )
        }
    }
}

@Composable
private fun AbsenceRiskLevel.riskColor(): Color = when (this) {
    AbsenceRiskLevel.SAFE -> MaterialTheme.colorScheme.primary
    AbsenceRiskLevel.WATCH -> RiskWatchOrange
    AbsenceRiskLevel.HIGH, AbsenceRiskLevel.OVER_LIMIT -> GradeyColors.Poor
    AbsenceRiskLevel.UNAVAILABLE -> MaterialTheme.colorScheme.onSurfaceVariant
}

@Composable
private fun DaysCard(timeline: AbsenceTimelineSummary, locale: java.util.Locale) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        if (timeline.days.isEmpty()) {
            EmptyState(stringResource(R.string.absence_days_empty))
        } else {
            Column {
                TotalsRow(timeline.total)
                timeline.days.forEach { day ->
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outlineVariant,
                        thickness = 0.33.dp,
                    )
                    DayRow(day, locale)
                }
            }
        }
    }
}

@Composable
private fun TotalsRow(counts: AbsenceCounts) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.absence_total),
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.onSurface,
            fontSize = 17.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.Bold,
        )
        CompactCountPills(counts)
        Text(
            text = counts.total.toString(),
            modifier = Modifier.width(34.dp),
            color = MaterialTheme.colorScheme.onSurface,
            fontSize = 17.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun DayRow(day: AbsenceDaySummary, locale: java.util.Locale) {
    val formatter = remember(locale) { DateTimeFormatter.ofPattern("EEE d. M.", locale) }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = day.date.format(formatter),
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.onSurface,
            fontSize = 16.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.SemiBold,
        )
        CompactCountPills(day.counts)
        Text(
            text = day.counts.total.toString(),
            modifier = Modifier.width(34.dp),
            color = MaterialTheme.colorScheme.onSurface,
            fontSize = 16.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun CompactCountPills(counts: AbsenceCounts) {
    val categories = AttendanceKind.entries.filter { it.value(counts) > 0 }
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        categories.take(4).forEach { kind -> CountPill(kind, kind.value(counts)) }
        if (categories.size > 4) OverflowPill(categories.size - 4)
    }
}

@Composable
private fun SectionHeading(text: String) {
    Text(
        text = text,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontSize = 14.sp,
        lineHeight = 18.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.6.sp,
    )
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
private fun MonthsChartCard(months: List<AbsenceMonthSummary>, locale: java.util.Locale) {
    val visibleCategories = AttendanceKind.entries.filter { kind ->
        months.any { kind.value(it.counts) > 0 }
    }
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 260.dp),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        Column {
            MonthBars(
                months = months,
                locale = locale,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(189.dp),
            )
            FlowRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, bottom = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                visibleCategories.forEach { kind ->
                    LegendPill(kind, kind.localizedLabel())
                }
            }
        }
    }
}

@Composable
private fun MonthBars(
    months: List<AbsenceMonthSummary>,
    locale: java.util.Locale,
    modifier: Modifier = Modifier,
) {
    val visibleMonths = months
    val maxMonth = visibleMonths.maxOfOrNull { it.counts.total } ?: 0
    val axisMax = max(10, ceil(maxMonth / 5.0).toInt() * 5)
    val monthNameFormatter = remember(locale) { DateTimeFormatter.ofPattern("LLLL yyyy", locale) }
    val narrowMonthFormatter = remember(locale) { DateTimeFormatter.ofPattern("LLLLL", locale) }
    val chartValues = visibleMonths.joinToString(separator = ", ") {
        "${it.month.atDay(1).format(monthNameFormatter)} ${it.counts.total}"
    }
    val chartDescription = stringResource(R.string.absence_chart_description, chartValues)
    val gridColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f)
    val attendanceColors = AttendanceKind.entries.associateWith { it.foregroundColor() }
    Box(
        modifier = modifier.semantics {
            contentDescription = chartDescription
        },
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val gridLeft = 16.dp.toPx()
            val gridRight = size.width - 32.dp.toPx()
            val plotTop = 16.dp.toPx()
            val plotBottom = 159.dp.toPx()
            val plotHeight = plotBottom - plotTop
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
                        colors = attendanceColors,
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
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
        )
        Text(
            text = (axisMax / 2).toString(),
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(end = 9.dp)
                .offset(y = 78.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
        )
        Text(
            text = "0",
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(end = 9.dp)
                .offset(y = 150.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                    text = month.month.atDay(1).format(narrowMonthFormatter),
                    modifier = Modifier.weight(1f),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
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
    colors: Map<AttendanceKind, Color>,
) {
    val segments = AttendanceKind.entries.mapNotNull { kind ->
        kind.value(counts).takeIf { it > 0 }?.let { it to colors.getValue(kind) }
    }
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
private fun MonthsCard(timeline: AbsenceTimelineSummary, locale: java.util.Locale) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        if (timeline.months.isEmpty()) {
            EmptyState(stringResource(R.string.absence_months_empty))
        } else {
            Column {
                TotalsRow(timeline.total)
                timeline.months.forEach { month ->
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outlineVariant,
                        thickness = 0.33.dp,
                    )
                    MonthRow(month, locale)
                }
            }
        }
    }
}

@Composable
private fun MonthRow(month: AbsenceMonthSummary, locale: java.util.Locale) {
    val formatter = remember(locale) { DateTimeFormatter.ofPattern("LLLL yyyy", locale) }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(49.dp)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = month.month.atDay(1).format(formatter),
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.onSurface,
            fontSize = 16.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.SemiBold,
        )
        CompactCountPills(month.counts)
        Text(
            text = month.counts.total.toString(),
            modifier = Modifier.width(34.dp),
            color = MaterialTheme.colorScheme.onSurface,
            fontSize = 16.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.End,
        )
    }
}

private enum class AttendanceKind {
    Unresolved,
    Excused,
    Missed,
    Late,
    Early,
    School,
    DistanceTeaching,
    ;

    fun value(counts: AbsenceCounts): Int = when (this) {
        Unresolved -> counts.unsolved
        Excused -> counts.ok
        Missed -> counts.missed
        Late -> counts.late
        Early -> counts.soon
        School -> counts.school
        DistanceTeaching -> counts.distanceTeaching
    }
}

@Composable
private fun AttendanceKind.foregroundColor(): Color = when (this) {
    AttendanceKind.Unresolved -> MaterialTheme.colorScheme.primary
    AttendanceKind.Excused,
    AttendanceKind.School,
    AttendanceKind.DistanceTeaching -> MaterialTheme.colorScheme.secondary
    AttendanceKind.Missed -> MissedRed
    AttendanceKind.Late -> LateOrange
    AttendanceKind.Early -> RiskWatchOrange
}

@Composable
private fun CountPill(kind: AttendanceKind, count: Int) {
    val accessibilityLabel = kind.localizedLabel()
    val foreground = kind.foregroundColor()
    Surface(
        modifier = Modifier.height(25.dp),
        shape = RoundedCornerShape(13.dp),
        color = foreground.copy(alpha = 0.14f),
        contentColor = foreground,
    ) {
        Row(
            modifier = Modifier
                .semantics { contentDescription = "$accessibilityLabel: $count" }
                .padding(horizontal = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            AttendanceIcon(kind)
            Text(
                text = count.toString(),
                color = foreground,
                fontSize = 14.sp,
                lineHeight = 17.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun OverflowPill(count: Int) {
    Surface(
        modifier = Modifier.height(25.dp),
        shape = RoundedCornerShape(13.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Text(
            text = stringResource(R.string.absence_overflow, count),
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp,
            lineHeight = 17.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun LegendPill(kind: AttendanceKind, label: String) {
    val foreground = kind.foregroundColor()
    Surface(
        modifier = Modifier.height(25.dp),
        shape = RoundedCornerShape(13.dp),
        color = foreground.copy(alpha = 0.14f),
        contentColor = foreground,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            AttendanceIcon(kind)
            Text(
                text = label,
                color = foreground,
                fontSize = 13.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun AttendanceIcon(kind: AttendanceKind) {
    val foreground = kind.foregroundColor()
    when (kind) {
        AttendanceKind.Unresolved -> Text("?", color = foreground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        AttendanceKind.Excused -> Icon(GradeyIcons.Tick, contentDescription = null, modifier = Modifier.size(14.dp))
        AttendanceKind.Missed -> Text("N", color = foreground, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        AttendanceKind.Late -> Text("P", color = foreground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        AttendanceKind.Early -> Text("O", color = foreground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        AttendanceKind.School -> Text("–", color = foreground, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        AttendanceKind.DistanceTeaching -> Text("D", color = foreground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun AttendanceKind.localizedLabel(): String = when (this) {
    AttendanceKind.Unresolved -> stringResource(R.string.absence_category_unsolved)
    AttendanceKind.Excused -> stringResource(R.string.absence_category_ok)
    AttendanceKind.Missed -> stringResource(R.string.absence_category_missed)
    AttendanceKind.Late -> stringResource(R.string.absence_category_late)
    AttendanceKind.Early -> stringResource(R.string.absence_category_soon)
    AttendanceKind.School -> stringResource(R.string.absence_category_school)
    AttendanceKind.DistanceTeaching -> stringResource(R.string.absence_category_distance_teaching)
}

@Composable
private fun EmptyState(text: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(80.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 14.sp,
        )
    }
}

private fun normalizedThreshold(value: Double?): Double? =
    value?.let { if (it in 0.0..1.0) it * 100.0 else it }?.takeIf { it > 0.0 }

private fun formatWhole(value: Double, locale: java.util.Locale): String =
    if (value % 1.0 == 0.0) value.toInt().toString() else String.format(locale, "%.1f", value)

private fun formatOneDecimal(value: Double, locale: java.util.Locale): String = String.format(locale, "%.1f", value)
