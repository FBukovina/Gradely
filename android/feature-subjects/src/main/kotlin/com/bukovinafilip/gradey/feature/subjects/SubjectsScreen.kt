package com.bukovinafilip.gradey.feature.subjects

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import com.bukovinafilip.gradey.ui.GradeyIcons
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import com.bukovinafilip.gradey.domain.AbsenceRiskSummary
import com.bukovinafilip.gradey.domain.AverageHistoryChart
import com.bukovinafilip.gradey.domain.AverageHistoryPolicy
import com.bukovinafilip.gradey.domain.AverageHistoryPoint
import com.bukovinafilip.gradey.domain.AverageHistorySource
import com.bukovinafilip.gradey.domain.GradeBand
import com.bukovinafilip.gradey.domain.GradeHistoryTrends
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.domain.MarkCardMetadataPolicy
import com.bukovinafilip.gradey.domain.MarkDateParser
import com.bukovinafilip.gradey.domain.MarkPredictionInput
import com.bukovinafilip.gradey.domain.MarkPredictionComparison
import com.bukovinafilip.gradey.domain.MarkWeightBadgeKind
import com.bukovinafilip.gradey.domain.SubjectDirectorySearch
import com.bukovinafilip.gradey.domain.SubjectDetailNotes
import com.bukovinafilip.gradey.domain.SubjectDetailNotesPolicy
import com.bukovinafilip.gradey.domain.SubjectGradeTrend
import com.bukovinafilip.gradey.domain.SubjectAttentionScore
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.ui.GradeyAuroraBackground
import com.bukovinafilip.gradey.ui.GradeyGradeBadge
import com.bukovinafilip.gradey.ui.GradeyRadius
import com.bukovinafilip.gradey.ui.GradeySectionHeader
import com.bukovinafilip.gradey.ui.GradeySpacing
import com.bukovinafilip.gradey.ui.color
import com.bukovinafilip.gradey.ui.softColor
import kotlinx.coroutines.CancellationException
import java.text.Collator
import java.text.Normalizer
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.roundToInt

private val AccentTeal = Color(0xFF17A185)
private val HeroStart = Color(0xFF18A182)
private val HeroEnd = Color(0xFF1CA567)
private val DetailHeroStart = Color(0xFF148A94)
private val DetailHeroEnd = Color(0xFF3099A1)
private val SoftTeal = Color(0xFFDEEFF0)
private val SoftMint = Color(0xFFE0F3EA)
private val ExcellentGreen = Color(0xFF18A56F)
private val WarningOrange = Color(0xFFE0921A)
private val DangerRed = Color(0xFFD95461)
private val PragueZone = ZoneId.of("Europe/Prague")

internal const val SUBJECT_SORT_TEST_TAG_PREFIX = "subjectSort:"
internal const val SUBJECT_STEPPER_DECREASE_TEST_TAG = "subjectStepperDecrease"
internal const val SUBJECT_STEPPER_INCREASE_TEST_TAG = "subjectStepperIncrease"

internal enum class SubjectSortMode {
    Focus,
    Average,
    Alphabetical,
}

@Composable
fun SubjectsScreen(
    subjects: List<Subject>,
    absence: AbsenceResponse,
    gradeTrends: List<SubjectGradeTrend> = emptyList(),
    onPredictSubjectAverage: suspend (Subject, String, Int) -> Double?,
    refreshErrorMessage: String? = null,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedSubjectID by rememberSaveable { mutableStateOf<String?>(null) }
    var sortMode by rememberSaveable { mutableStateOf(SubjectSortMode.Focus) }
    var searchQuery by rememberSaveable { mutableStateOf("") }
    val selectedSubject = subjects.firstOrNull { it.id == selectedSubjectID }
    val selectedTrend = remember(selectedSubject, gradeTrends) {
        selectedSubject?.let { GradeHistoryTrends.matching(it, gradeTrends) }
    }

    LaunchedEffect(selectedSubjectID, subjects) {
        if (selectedSubjectID != null && selectedSubject == null) selectedSubjectID = null
    }
    BackHandler(enabled = selectedSubject != null) { selectedSubjectID = null }

    if (selectedSubject == null) {
        SubjectsOverview(
            subjects = subjects,
            absence = absence,
            gradeTrends = gradeTrends,
            refreshErrorMessage = refreshErrorMessage,
            sortMode = sortMode,
            onSortModeChange = { sortMode = it },
            searchQuery = searchQuery,
            onSearchQueryChange = { searchQuery = it },
            isRefreshing = isRefreshing,
            onRefresh = onRefresh,
            onOpenAccount = onOpenAccount,
            onOpenGradeyTools = onOpenGradeyTools,
            onOpenSubject = { selectedSubjectID = it.id },
            modifier = modifier,
        )
    } else {
        SubjectDetail(
            subject = selectedSubject,
            absence = absence,
            trend = selectedTrend,
            onPredictSubjectAverage = onPredictSubjectAverage,
            onBack = { selectedSubjectID = null },
            modifier = modifier,
        )
    }
}

@Composable
private fun SubjectsOverview(
    subjects: List<Subject>,
    absence: AbsenceResponse,
    gradeTrends: List<SubjectGradeTrend>,
    refreshErrorMessage: String?,
    sortMode: SubjectSortMode,
    onSortModeChange: (SubjectSortMode) -> Unit,
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    onOpenSubject: (Subject) -> Unit,
    modifier: Modifier = Modifier,
) {
    val absenceRows = remember(absence) {
        AbsenceRiskSummary.make(absence, absence.absencesPerSubject).subjects.associateBy { it.subjectName.subjectKey() }
    }
    val filteredSubjects = remember(subjects, searchQuery) {
        SubjectDirectorySearch.results(searchQuery, subjects)
    }
    val trendsBySubjectID = remember(subjects, gradeTrends) {
        subjects.associate { it.id to GradeHistoryTrends.matching(it, gradeTrends) }
    }
    val recentTrends = remember(gradeTrends) {
        GradeHistoryTrends.since(
            gradeTrends,
            Instant.now().minus(90, ChronoUnit.DAYS),
        ).take(4)
    }
    val sortedSubjects = remember(filteredSubjects, absenceRows, trendsBySubjectID, sortMode) {
        when (sortMode) {
            SubjectSortMode.Focus -> filteredSubjects.sortedWith(
                compareByDescending<Subject> {
                    SubjectAttentionScore.value(
                        subject = it,
                        absencePercentage = absenceRows[it.displayName.subjectKey()]?.absencePercentage,
                        trend = trendsBySubjectID[it.id],
                    )
                }.thenBy { it.displayName },
            )

            SubjectSortMode.Average -> filteredSubjects.sortedWith(
                compareBy<Subject> { GradeMath.subjectAverage(it) ?: Double.MAX_VALUE }.thenBy { it.displayName },
            )

            SubjectSortMode.Alphabetical -> {
                val collator = Collator.getInstance(Locale.forLanguageTag("cs-CZ"))
                filteredSubjects.sortedWith { first, second -> collator.compare(first.displayName, second.displayName) }
            }
        }
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
            contentPadding = PaddingValues(start = 16.dp, top = 13.dp, end = 16.dp, bottom = 126.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                MarksHeader(
                    title = stringResource(R.string.marks_title),
                    isRefreshing = isRefreshing,
                    onRefresh = onRefresh,
                    onOpenAccount = onOpenAccount,
                    onOpenGradeyTools = onOpenGradeyTools,
                )
            }
            if (refreshErrorMessage != null) {
                item {
                    MarksRefreshErrorCard(
                        errorMessage = refreshErrorMessage,
                        isRefreshing = isRefreshing,
                        onRetry = onRefresh,
                    )
                }
            }
            item { OverallAverageCard(subjects) }
            if (recentTrends.isNotEmpty()) {
                item { GradeMovementSection(recentTrends) }
            }
            item {
                SubjectSearchField(
                    query = searchQuery,
                    onQueryChange = onSearchQueryChange,
                )
            }
            item {
                Column {
                    SubjectsSectionHeader(sortMode = sortMode, onSortModeChange = onSortModeChange)
                    Spacer(Modifier.height(12.dp))
                    SubjectsCard(
                        subjects = sortedSubjects,
                        absenceByName = absenceRows,
                        trendsBySubjectID = trendsBySubjectID,
                        emptyMessage = if (searchQuery.isBlank()) {
                            stringResource(R.string.marks_empty)
                        } else {
                            stringResource(R.string.marks_search_empty)
                        },
                        onOpenSubject = onOpenSubject,
                    )
                }
            }
        }
    }
}

@Composable
private fun MarksRefreshErrorCard(
    errorMessage: String,
    isRefreshing: Boolean,
    onRetry: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = DangerRed.copy(alpha = 0.12f),
    ) {
        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp)) {
            Text(
                text = stringResource(R.string.marks_refresh_failed_title),
                color = DangerRed,
                fontSize = 15.sp,
                lineHeight = 18.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text = stringResource(R.string.marks_refresh_failed_cached),
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 13.sp,
                lineHeight = 17.sp,
            )
            Text(
                text = errorMessage,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 12.sp,
                lineHeight = 16.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(8.dp))
            Surface(
                onClick = onRetry,
                enabled = !isRefreshing,
                shape = RoundedCornerShape(10.dp),
                color = MaterialTheme.colorScheme.surfaceContainer,
                contentColor = DangerRed,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    if (isRefreshing) {
                        CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(GradeyIcons.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                    }
                    Text(
                        text = stringResource(R.string.marks_refresh_retry),
                        fontSize = 13.sp,
                        lineHeight = 16.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

@Composable
private fun SubjectSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
) {
    val prompt = stringResource(R.string.marks_search_prompt)
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        placeholder = { Text(prompt) },
        leadingIcon = {
            Icon(GradeyIcons.Search, contentDescription = null)
        },
        trailingIcon = if (query.isNotEmpty()) {
            {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(GradeyIcons.Cancel, contentDescription = stringResource(R.string.marks_search_clear))
                }
            }
        } else {
            null
        },
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Text,
            imeAction = ImeAction.Search,
        ),
        shape = RoundedCornerShape(16.dp),
    )
}

@Composable
private fun MarksHeader(
    title: String,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
) {
    val openToolsDescription = stringResource(R.string.marks_open_gradey_tools)
    val refreshDescription = stringResource(R.string.marks_refresh_content_description)
    val openAccountDescription = stringResource(R.string.marks_open_account)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp),
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
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(22.dp),
                            )
                        }
                    }
                }
            }
        }

        Text(
            text = title,
            color = MaterialTheme.colorScheme.onBackground,
            fontSize = 18.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.SemiBold,
        )

        Box(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .width(105.dp)
                .height(48.dp),
        ) {
            Surface(
                modifier = Modifier
                    .align(Alignment.Center)
                    .fillMaxWidth()
                    .height(44.dp),
                shape = RoundedCornerShape(22.dp),
                color = MaterialTheme.colorScheme.surfaceContainer,
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
                            color = MaterialTheme.colorScheme.primary,
                            strokeWidth = 2.5.dp,
                        )
                    } else {
                        Icon(
                            imageVector = GradeyIcons.Refresh,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
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
                        modifier = Modifier.size(32.dp),
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = GradeyIcons.User,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
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
private fun OverallAverageCard(subjects: List<Subject>) {
    val overallAverage = formatAverage(GradeMath.overallAverage(subjects))
    val totalMarks = subjects.sumOf { it.marks.size }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(124.dp),
        shape = RoundedCornerShape(GradeyRadius.card),
        color = Color.Transparent,
        shadowElevation = 2.dp,
    ) {
        Row(
            modifier = Modifier
                .background(Brush.horizontalGradient(listOf(HeroStart, HeroEnd)))
                .padding(horizontal = GradeySpacing.xl, vertical = 20.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Column {
                Text(
                    text = stringResource(R.string.marks_overall_average),
                    color = Color(0xFF073C35),
                    fontSize = 14.sp,
                    lineHeight = 18.sp,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    text = overallAverage,
                    color = Color(0xFF001D19),
                    fontSize = 50.sp,
                    lineHeight = 55.sp,
                    fontWeight = FontWeight.ExtraBold,
                )
            }
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(1.dp),
            ) {
                Text(
                    text = pluralStringResource(R.plurals.marks_subject_count, subjects.size, subjects.size),
                    color = Color(0xFF073C35),
                    fontSize = 14.sp,
                    lineHeight = 18.sp,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    text = pluralStringResource(R.plurals.subject_mark_count, totalMarks, totalMarks),
                    color = Color(0xFF073C35),
                    fontSize = 14.sp,
                    lineHeight = 18.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

@Composable
internal fun SubjectsSectionHeader(
    sortMode: SubjectSortMode,
    onSortModeChange: (SubjectSortMode) -> Unit,
) {
    BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
        val stackControls = maxWidth < 300.dp || LocalDensity.current.fontScale >= 1.5f
        if (stackControls) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                GradeySectionHeader(stringResource(R.string.marks_subjects_section))
                SubjectSortPicker(
                    sortMode = sortMode,
                    onSortModeChange = onSortModeChange,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        } else {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                GradeySectionHeader(
                    text = stringResource(R.string.marks_subjects_section),
                    modifier = Modifier
                        .weight(1f)
                        .padding(end = 8.dp),
                )
                SubjectSortPicker(
                    sortMode = sortMode,
                    onSortModeChange = onSortModeChange,
                    modifier = Modifier.width(180.dp),
                )
            }
        }
    }
}

@Composable
private fun SubjectSortPicker(
    sortMode: SubjectSortMode,
    onSortModeChange: (SubjectSortMode) -> Unit,
    modifier: Modifier,
) {
    val useExpandableTrack = LocalDensity.current.fontScale >= 1.5f
    Box(
        modifier = modifier.heightIn(min = 48.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = if (useExpandableTrack) {
                Modifier.matchParentSize()
            } else {
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 31.dp)
            },
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceVariant,
        ) {}
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .selectableGroup()
                .padding(horizontal = 1.dp),
        ) {
            SortSegment(
                modifier = Modifier
                    .weight(55f)
                    .widthIn(min = 48.dp),
                mode = SubjectSortMode.Focus,
                selected = sortMode == SubjectSortMode.Focus,
                onClick = { onSortModeChange(SubjectSortMode.Focus) },
            )
            SortSegment(
                modifier = Modifier
                    .weight(75f)
                    .widthIn(min = 48.dp),
                mode = SubjectSortMode.Average,
                selected = sortMode == SubjectSortMode.Average,
                onClick = { onSortModeChange(SubjectSortMode.Average) },
            )
            SortSegment(
                modifier = Modifier
                    .weight(48f)
                    .widthIn(min = 48.dp),
                mode = SubjectSortMode.Alphabetical,
                selected = sortMode == SubjectSortMode.Alphabetical,
                onClick = { onSortModeChange(SubjectSortMode.Alphabetical) },
            )
        }
    }
}

@Composable
internal fun SortSegment(
    modifier: Modifier,
    mode: SubjectSortMode,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .heightIn(min = 48.dp)
            .testTag(SUBJECT_SORT_TEST_TAG_PREFIX + mode.name)
            .selectable(
                selected = selected,
                role = Role.Tab,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 29.dp),
            shape = RoundedCornerShape(15.dp),
            color = if (selected) MaterialTheme.colorScheme.surface else Color.Transparent,
            shadowElevation = if (selected) 1.dp else 0.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                val label = when (mode) {
                    SubjectSortMode.Focus -> stringResource(R.string.marks_sort_focus)
                    SubjectSortMode.Average -> stringResource(R.string.marks_sort_average)
                    SubjectSortMode.Alphabetical -> stringResource(R.string.marks_sort_name)
                }
                Text(
                    text = label,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = 14.sp,
                    lineHeight = 17.sp,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    maxLines = 2,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun SubjectsCard(
    subjects: List<Subject>,
    absenceByName: Map<String, com.bukovinafilip.gradey.domain.AbsenceSubjectSummary>,
    trendsBySubjectID: Map<String, SubjectGradeTrend?>,
    emptyMessage: String,
    onOpenSubject: (Subject) -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        if (subjects.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(68.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(emptyMessage, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
            }
        } else {
            Column {
                subjects.forEachIndexed { index, subject ->
                    SubjectRow(
                        subject = subject,
                        absencePercentage = absenceByName[subject.displayName.subjectKey()]?.absencePercentage,
                        trend = trendsBySubjectID[subject.id],
                        onClick = { onOpenSubject(subject) },
                    )
                    if (index != subjects.lastIndex) {
                        HorizontalDivider(
                            modifier = Modifier.padding(start = 68.dp),
                            thickness = 0.5.dp,
                            color = MaterialTheme.colorScheme.outlineVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SubjectRow(
    subject: Subject,
    absencePercentage: Double?,
    trend: SubjectGradeTrend?,
    onClick: () -> Unit,
) {
    val average = GradeMath.subjectAverage(subject)
    val (bandBackground, bandForeground) = GradeMath.band(average).subjectColors()
    val latestMark = MarkDateParser.newestFirst(subject.marks, PragueZone, Mark::markDate).firstOrNull()
    val trendDelta = trend?.averageDelta?.takeUnless { it == 0.0 }
    val trendDescription = trendDelta?.let { delta ->
        stringResource(
            if (delta < 0) R.string.subject_trend_better else R.string.subject_trend_worse,
            String.format(Locale.getDefault(), "%.2f", kotlin.math.abs(delta)),
        )
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(68.dp)
            .clickable(onClick = onClick)
            .padding(start = 12.dp, end = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            modifier = Modifier
                .width(44.dp)
                .height(40.dp),
            shape = RoundedCornerShape(12.dp),
            color = bandBackground,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    text = subject.subjectInfo.abbrev.ifBlank { subject.displayName.take(2) },
                    color = bandForeground,
                    fontSize = 17.sp,
                    lineHeight = 20.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = subject.displayName,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 18.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.Bold,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                val markCount = subject.marks.size
                Text(
                    text = pluralStringResource(R.plurals.subject_mark_count, markCount, markCount),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 16.sp,
                    lineHeight = 19.sp,
                )
                latestMark?.let {
                    Spacer(Modifier.width(8.dp))
                    InlineMarkPill(mark = it)
                }
                trendDelta?.let { delta ->
                    Spacer(Modifier.width(6.dp))
                    Icon(
                        imageVector = if (delta < 0) {
                            GradeyIcons.TrendingDown
                        } else {
                            GradeyIcons.TrendingUp
                        },
                        contentDescription = null,
                        tint = if (delta < 0) AccentTeal else DangerRed,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        text = String.format(Locale.getDefault(), "%+.2f", delta),
                        color = if (delta < 0) AccentTeal else DangerRed,
                        fontSize = 12.sp,
                        lineHeight = 15.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.semantics {
                            contentDescription = trendDescription.orEmpty()
                        },
                    )
                }
            }
        }
        Column(
            modifier = Modifier.width(80.dp),
            horizontalAlignment = Alignment.End,
        ) {
            Text(
                text = formatAverage(average),
                color = bandForeground,
                fontSize = 20.sp,
                lineHeight = 23.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = absencePercentage?.let { stringResource(R.string.marks_row_absence, it.roundToInt()) }
                    ?: stringResource(R.string.subject_absence_unavailable),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 14.sp,
                lineHeight = 17.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
        }
        Spacer(Modifier.width(4.dp))
        Icon(
            imageVector = GradeyIcons.ArrowRight,
            contentDescription = stringResource(R.string.marks_open_subject, subject.displayName),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun GradeMovementSection(trends: List<SubjectGradeTrend>) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GradeySectionHeader(
                text = stringResource(R.string.marks_trends_section),
                modifier = Modifier
                    .weight(1f)
                    .padding(end = 8.dp),
            )
            Text(
                text = stringResource(R.string.marks_trends_range),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp,
                lineHeight = 17.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Spacer(Modifier.height(12.dp))
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            color = MaterialTheme.colorScheme.surfaceContainer,
            shadowElevation = 1.dp,
        ) {
            Column {
                trends.forEachIndexed { index, trend ->
                    GradeMovementRow(trend)
                    if (index != trends.lastIndex) {
                        HorizontalDivider(
                            modifier = Modifier.padding(start = 16.dp),
                            thickness = 0.5.dp,
                            color = MaterialTheme.colorScheme.outlineVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun GradeMovementRow(trend: SubjectGradeTrend) {
    val values = trend.events.mapNotNull { it.averageValue }
    val (background, foreground) = GradeMath.band(trend.latestAverage).subjectColors()
    val newMarks = (trend.latestMarkCount - trend.firstMarkCount).coerceAtLeast(0)
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
            color = background,
        ) {
            GradeMovementSparkline(values, foreground)
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = trend.displayName,
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 15.sp,
                lineHeight = 18.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = if (newMarks > 0) {
                    pluralStringResource(R.plurals.marks_trends_new_marks, newMarks, newMarks)
                } else {
                    stringResource(R.string.marks_trends_movement)
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 12.sp,
                lineHeight = 15.sp,
            )
        }
        trend.averageDelta?.let { delta ->
            Text(
                text = String.format(Locale.getDefault(), "%+.2f", delta),
                color = if (delta > 0) DangerRed else AccentTeal,
                fontSize = 15.sp,
                lineHeight = 18.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun GradeMovementSparkline(values: List<Double>, color: Color) {
    Canvas(modifier = Modifier.fillMaxSize().padding(horizontal = 6.dp, vertical = 7.dp)) {
        if (values.isEmpty()) return@Canvas
        val minimum = values.minOrNull() ?: return@Canvas
        val maximum = values.maxOrNull() ?: return@Canvas
        val range = (maximum - minimum).takeIf { it > 0.001 } ?: 1.0
        val offsets = values.mapIndexed { index, value ->
            val x = if (values.size == 1) size.width / 2f else size.width * index / values.lastIndex.toFloat()
            val y = size.height * ((value - minimum) / range).toFloat()
            Offset(x, y)
        }
        if (offsets.size > 1) {
            val path = Path().apply {
                moveTo(offsets.first().x, offsets.first().y)
                offsets.drop(1).forEach { lineTo(it.x, it.y) }
            }
            drawPath(
                path = path,
                color = color,
                style = Stroke(width = 1.8.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
            )
        }
        offsets.forEach { drawCircle(color, radius = 2.dp.toPx(), center = it) }
    }
}

@Composable
private fun SubjectDetail(
    subject: Subject,
    absence: AbsenceResponse,
    trend: SubjectGradeTrend?,
    onPredictSubjectAverage: suspend (Subject, String, Int) -> Double?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()
    val isScrolled by remember {
        derivedStateOf { listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 60 }
    }
    val absenceRow = remember(subject.id, absence) {
        AbsenceRiskSummary.make(absence, absence.absencesPerSubject).subjects
            .firstOrNull { it.subjectName.subjectKey() == subject.displayName.subjectKey() }
    }
    var trialMark by rememberSaveable(subject.id) { mutableStateOf("") }
    var trialWeight by rememberSaveable(subject.id) { mutableIntStateOf(1) }
    var exactPredictedAverage by remember(subject.id) { mutableStateOf<Double?>(null) }
    var isPredictingExactAverage by remember(subject.id) { mutableStateOf(false) }
    val trialValue = remember(trialMark) { MarkPredictionInput.markValue(trialMark) }
    val trialMarkError = if (MarkPredictionInput.isInvalid(trialMark)) {
        stringResource(R.string.mark_prediction_invalid)
    } else {
        null
    }
    val currentAverage = remember(subject) { GradeMath.subjectAverage(subject) }
    val localPredictedAverage = remember(subject, trialValue, trialWeight) {
        trialValue?.let {
            GradeMath.theoreticalAverage(
                existingMarks = subject.marks,
                subjectAverageText = subject.averageText,
                markValue = it,
                weight = trialWeight,
            )
        }
    }
    val predictedAverage = exactPredictedAverage ?: localPredictedAverage
    val calculatorEnabled = !subject.pointsOnly
    val remotePredictionEnabled = calculatorEnabled && subject.markPredictionEnabled
    val notes = remember(subject) { SubjectDetailNotesPolicy.resolve(subject) }
    val historyChart = remember(subject, trend) { AverageHistoryPolicy.resolve(subject, trend, PragueZone) }
    val isDarkTheme = isSystemInDarkTheme()

    LaunchedEffect(subject.id, trialMark, trialWeight, remotePredictionEnabled) {
        exactPredictedAverage = null
        isPredictingExactAverage = false
        if (trialValue == null || !remotePredictionEnabled) return@LaunchedEffect
        isPredictingExactAverage = true
        try {
            exactPredictedAverage = onPredictSubjectAverage(subject, trialMark, trialWeight)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Keep the already-computed local result and current subject content.
        } finally {
            isPredictingExactAverage = false
        }
    }

    StatusBarAppearance(
        useDarkIcons = !isDarkTheme && !isScrolled,
        restoreDarkIcons = !isDarkTheme,
    )

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        GradeyAuroraBackground()
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            contentPadding = PaddingValues(start = 16.dp, top = 117.dp, end = 16.dp, bottom = 126.dp),
        ) {
            item {
                SubjectAverageHero(
                    average = currentAverage,
                    predicted = false,
                    markCount = subject.marks.size,
                    absencePercentage = absenceRow?.absencePercentage,
                )
            }
            if (notes.hasContent) {
                item { Spacer(Modifier.height(16.dp)) }
                item { GradeySectionHeader(stringResource(R.string.subject_notes_section)) }
                item { Spacer(Modifier.height(10.dp)) }
                item { SubjectNotesCard(notes) }
            }
            item { Spacer(Modifier.height(16.dp)) }
            item { GradeySectionHeader(stringResource(R.string.subject_history_section)) }
            item { Spacer(Modifier.height(18.dp)) }
            item { AverageChartCard(historyChart) }
            item { Spacer(Modifier.height(10.dp)) }
            item { GradeySectionHeader(stringResource(R.string.subject_prediction_section)) }
            item { Spacer(Modifier.height(24.dp)) }
            item {
                TryMarkCard(
                    value = trialMark,
                    weight = trialWeight,
                    enabled = calculatorEnabled,
                    errorMessage = trialMarkError,
                    currentAverage = currentAverage,
                    predictedAverage = predictedAverage,
                    isPredictingExactAverage = isPredictingExactAverage,
                    isExactAverage = exactPredictedAverage != null,
                    onValueChange = { trialMark = MarkPredictionInput.acceptedMarkText(trialMark, it) },
                    onDecreaseWeight = { trialWeight = MarkPredictionInput.decreaseWeight(trialWeight) },
                    onIncreaseWeight = { trialWeight = MarkPredictionInput.increaseWeight(trialWeight) },
                )
            }
            item { Spacer(Modifier.height(8.dp)) }
            item { GradeySectionHeader(stringResource(R.string.subject_marks_section)) }
            item { Spacer(Modifier.height(25.dp)) }
            if (subject.marks.isEmpty()) {
                item { EmptyMarksCard() }
            } else {
                items(
                    items = MarkDateParser.newestFirst(subject.marks, PragueZone, Mark::markDate),
                    key = Mark::id,
                ) { mark ->
                    MarkCard(subject = subject, mark = mark)
                    Spacer(Modifier.height(12.dp))
                }
            }
        }

        SubjectDetailHeader(
            title = subject.displayName,
            isScrolled = isScrolled,
            onBack = onBack,
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }
}

@Composable
private fun SubjectDetailHeader(
    title: String,
    isScrolled: Boolean,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(101.dp)
            .background(
                if (isScrolled) Color(0xE61A7B80) else Color.Transparent,
            ),
    )
    Box(
        modifier = modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(top = 13.dp, start = 16.dp, end = 16.dp)
            .height(64.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(44.dp),
            onClick = onBack,
            shape = CircleShape,
            color = if (isScrolled) Color(0xFFA3E3E6) else MaterialTheme.colorScheme.surfaceContainer,
            shadowElevation = 2.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = GradeyIcons.ArrowLeft,
                    contentDescription = stringResource(R.string.subject_back),
                    tint = if (isScrolled) Color(0xFF061C1B) else MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(28.dp),
                )
            }
        }
        Text(
            text = title,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            color = if (isScrolled) Color.White else MaterialTheme.colorScheme.onBackground,
            fontSize = 17.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun SubjectAverageHero(
    average: Double?,
    predicted: Boolean,
    markCount: Int,
    absencePercentage: Double?,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(194.dp),
        shape = RoundedCornerShape(GradeyRadius.card),
        color = Color.Transparent,
        shadowElevation = 2.dp,
    ) {
        Column(
            modifier = Modifier
                .background(Brush.horizontalGradient(listOf(DetailHeroStart, DetailHeroEnd)))
                .padding(top = GradeySpacing.xl, bottom = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = stringResource(
                    if (predicted) R.string.subject_predicted_average else R.string.subject_average,
                ),
                color = Color.White,
                fontSize = 17.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(10.dp))
            Text(
                text = formatAverage(average),
                color = Color.White,
                fontSize = 66.sp,
                lineHeight = 70.sp,
                fontWeight = FontWeight.ExtraBold,
            )
            Spacer(Modifier.height(18.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                DetailChip(
                    icon = { Icon(GradeyIcons.CheckmarkBadge, contentDescription = null, modifier = Modifier.size(14.dp)) },
                    text = pluralStringResource(R.plurals.subject_mark_count, markCount, markCount),
                )
                DetailChip(
                    icon = { Icon(GradeyIcons.Calendar, contentDescription = null, modifier = Modifier.size(14.dp)) },
                    text = absencePercentage?.let {
                        stringResource(R.string.subject_absence, formatOneDecimal(it))
                    } ?: stringResource(R.string.subject_absence_unavailable),
                )
            }
        }
    }
}

@Composable
private fun SubjectNotesCard(notes: SubjectDetailNotes) {
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
            notes.subjectNote?.let { note ->
                NoteBlock(
                    label = stringResource(R.string.subject_note_label),
                    value = note,
                )
            }
            if (notes.subjectNote != null && notes.hasTemporaryContent) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
            if (notes.hasTemporaryContent) {
                Text(
                    text = stringResource(R.string.subject_temporary_mark_label),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 13.sp,
                    lineHeight = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                notes.temporaryMark?.let { mark ->
                    Text(
                        text = mark,
                        color = AccentTeal,
                        fontSize = 22.sp,
                        lineHeight = 26.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
                notes.temporaryMarkNote?.let { note ->
                    Text(
                        text = note,
                        color = MaterialTheme.colorScheme.onSurface,
                        fontSize = 15.sp,
                        lineHeight = 20.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun NoteBlock(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
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
            fontSize = 15.sp,
            lineHeight = 20.sp,
        )
    }
}

@Composable
private fun DetailChip(
    icon: @Composable () -> Unit,
    text: String,
) {
    Surface(
        modifier = Modifier.height(28.dp),
        shape = RoundedCornerShape(14.dp),
        color = Color.White.copy(alpha = 0.22f),
        contentColor = Color.White,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            icon()
            Text(
                text = text,
                color = Color.White,
                fontSize = 14.sp,
                lineHeight = 17.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

@Composable
private fun AverageChartCard(chart: AverageHistoryChart) {
    if (chart.source == AverageHistorySource.NONE) {
        EmptyAverageChartCard()
        return
    }
    val points = chart.points
    val values = points.map(AverageHistoryPoint::average)
    val topValue = ((values.minOrNull()!! * 10.0).roundToInt() - 1) / 10.0
    val bottomValue = ((values.maxOrNull()!! * 10.0).roundToInt() + 1) / 10.0
    val safeBottomValue = if (bottomValue <= topValue) topValue + 0.2 else bottomValue
    val dateLabels = when (points.size) {
        1 -> listOf(points.single().date?.shortDate() ?: "—")
        2 -> points.map { it.date?.shortDate() ?: "—" }
        else -> listOf(points.first(), points[points.lastIndex / 2], points.last())
            .map { it.date?.shortDate() ?: "—" }
    }
    val sourceCaption = stringResource(
        if (chart.source == AverageHistorySource.CLOUD) {
            R.string.subject_history_source_cloud
        } else {
            R.string.subject_history_source_local
        },
    )
    val delta = chart.averageDelta?.let { String.format(Locale.getDefault(), "%+.2f", it) }
    val chartDescription = pluralStringResource(
        R.plurals.subject_average_chart_description,
        points.size,
        points.size,
    )
    val gridColor = MaterialTheme.colorScheme.outlineVariant
    val pointBackground = MaterialTheme.colorScheme.surfaceContainer

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(237.dp)
            .semantics {
                contentDescription = chartDescription
            },
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val xStart = 16.dp.toPx()
                val xEnd = size.width - 36.dp.toPx()
                val yTop = 51.dp.toPx()
                val yBottom = 114.dp.toPx()
                drawLine(gridColor, Offset(xStart, yTop), Offset(xEnd, yTop), strokeWidth = 0.7.dp.toPx())
                drawLine(gridColor, Offset(xStart, yBottom), Offset(xEnd, yBottom), strokeWidth = 0.7.dp.toPx())

                val offsets = points.mapIndexed { index, point ->
                    val x = if (points.size == 1) {
                        (xStart + xEnd) / 2f
                    } else {
                        xStart + (xEnd - xStart) * index.toFloat() / points.lastIndex.toFloat()
                    }
                    val progress = ((point.average - topValue) / (safeBottomValue - topValue)).coerceIn(0.0, 1.0)
                    val y = yTop + (yBottom - yTop) * progress.toFloat()
                    Offset(x, y)
                }
                if (offsets.size > 1) {
                    val path = Path().apply {
                        moveTo(offsets.first().x, offsets.first().y)
                        offsets.drop(1).forEach { lineTo(it.x, it.y) }
                    }
                    drawPath(
                        path = path,
                        color = Color(0xFF1396A0),
                        style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
                    )
                }
                offsets.forEach { point ->
                    drawCircle(pointBackground, radius = 6.dp.toPx(), center = point)
                    drawCircle(Color(0xFF1396A0), radius = 4.5.dp.toPx(), center = point)
                }
            }

            Text(
                text = formatOneDecimal(topValue),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 44.dp, end = 16.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp,
                lineHeight = 17.sp,
            )
            Text(
                text = formatOneDecimal(safeBottomValue),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 107.dp, end = 16.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp,
                lineHeight = 17.sp,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .offset(y = 170.dp)
                    .padding(start = 54.dp),
            ) {
                dateLabels.forEach { label ->
                    Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        Text(
                            label,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 13.sp,
                            lineHeight = 17.sp,
                        )
                    }
                }
            }
            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, bottom = 20.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    sourceCaption,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 13.sp,
                    lineHeight = 17.sp,
                )
                delta?.let {
                    Text(
                        text = it,
                        color = if ((chart.averageDelta ?: 0.0) > 0) DangerRed else AccentTeal,
                        fontSize = 13.sp,
                        lineHeight = 17.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyAverageChartCard() {
    val title = stringResource(R.string.subject_history_empty_title)
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(160.dp)
            .semantics { contentDescription = title },
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = title,
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 17.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = stringResource(R.string.subject_history_empty_body),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp,
                lineHeight = 18.sp,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun TryMarkCard(
    value: String,
    weight: Int,
    enabled: Boolean,
    errorMessage: String?,
    currentAverage: Double?,
    predictedAverage: Double?,
    isPredictingExactAverage: Boolean,
    isExactAverage: Boolean,
    onValueChange: (String) -> Unit,
    onDecreaseWeight: () -> Unit,
    onIncreaseWeight: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = if (errorMessage == null) 138.dp else 158.dp),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        Column(modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 16.dp)) {
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                enabled = enabled,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(46.dp)
                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(13.dp))
                    .padding(horizontal = 13.dp),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                textStyle = TextStyle(
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = 18.sp,
                    lineHeight = 22.sp,
                ),
                decorationBox = { field ->
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) {
                        if (value.isEmpty()) {
                            Text(
                                text = stringResource(
                                    if (enabled) R.string.subject_prediction_placeholder else R.string.subject_prediction_unavailable,
                                ),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 18.sp,
                                lineHeight = 22.sp,
                            )
                        }
                        field()
                    }
                },
            )
            if (errorMessage != null) {
                Text(
                    text = errorMessage,
                    color = MaterialTheme.colorScheme.error,
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                )
            }
            Spacer(Modifier.height(14.dp))
            PredictionWeightStepperRow(
                enabled = enabled,
                weight = weight,
                onDecreaseWeight = onDecreaseWeight,
                onIncreaseWeight = onIncreaseWeight,
            )
            predictedAverage?.let { predicted ->
                Spacer(Modifier.height(12.dp))
                PredictionResultPanel(
                    currentAverage = currentAverage,
                    predictedAverage = predicted,
                    isPredictingExactAverage = isPredictingExactAverage,
                    isExactAverage = isExactAverage,
                )
            }
        }
    }
}

@Composable
internal fun PredictionWeightStepperRow(
    enabled: Boolean,
    weight: Int,
    onDecreaseWeight: () -> Unit,
    onIncreaseWeight: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(13.dp))
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepperButton(
            enabled = enabled && weight > 1,
            onClick = onDecreaseWeight,
            testTag = SUBJECT_STEPPER_DECREASE_TEST_TAG,
            contentDescription = stringResource(R.string.subject_prediction_decrease_weight),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f),
        ) {
            Icon(GradeyIcons.Minus, contentDescription = null, modifier = Modifier.size(22.dp))
        }
        Text(
            text = stringResource(R.string.subject_prediction_weight, weight),
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.onSurface,
            fontSize = 17.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            textAlign = TextAlign.Center,
        )
        StepperButton(
            enabled = enabled && weight < 10,
            onClick = onIncreaseWeight,
            testTag = SUBJECT_STEPPER_INCREASE_TEST_TAG,
            contentDescription = stringResource(R.string.subject_prediction_increase_weight),
            tint = MaterialTheme.colorScheme.primary,
        ) {
            Icon(GradeyIcons.Add, contentDescription = null, modifier = Modifier.size(27.dp))
        }
    }
}

@Composable
private fun PredictionResultPanel(
    currentAverage: Double?,
    predictedAverage: Double,
    isPredictingExactAverage: Boolean,
    isExactAverage: Boolean,
) {
    val comparison = MarkPredictionInput.comparison(currentAverage, predictedAverage)
    val difference = currentAverage?.let { predictedAverage - it }
    val tint = when (comparison) {
        MarkPredictionComparison.BETTER -> AccentTeal
        MarkPredictionComparison.WORSE -> DangerRed
        MarkPredictionComparison.SAME,
        MarkPredictionComparison.UNKNOWN -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val comparisonText = when (comparison) {
        MarkPredictionComparison.BETTER -> stringResource(
            R.string.subject_prediction_better,
            formatAverage(kotlin.math.abs(difference ?: 0.0)),
        )
        MarkPredictionComparison.WORSE -> stringResource(
            R.string.subject_prediction_worse,
            formatAverage(difference ?: 0.0),
        )
        MarkPredictionComparison.SAME -> stringResource(R.string.subject_prediction_same)
        MarkPredictionComparison.UNKNOWN -> null
    }
    val source = stringResource(
        when {
            isPredictingExactAverage -> R.string.subject_prediction_checking
            isExactAverage -> R.string.subject_prediction_exact
            else -> R.string.subject_prediction_local
        },
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(tint.copy(alpha = 0.11f), RoundedCornerShape(13.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = stringResource(R.string.subject_prediction_new_average, formatAverage(predictedAverage)),
            color = MaterialTheme.colorScheme.onSurface,
            fontSize = 18.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.Bold,
        )
        comparisonText?.let {
            Spacer(Modifier.height(3.dp))
            Text(it, color = tint, fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (isPredictingExactAverage) {
                CircularProgressIndicator(
                    modifier = Modifier.size(12.dp),
                    strokeWidth = 1.5.dp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(source, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp, lineHeight = 15.sp)
        }
    }
}

@Composable
internal fun StepperButton(
    enabled: Boolean,
    onClick: () -> Unit,
    testTag: String,
    contentDescription: String,
    tint: Color,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(48.dp)
            .testTag(testTag)
            .clip(RoundedCornerShape(12.dp))
            .semantics { this.contentDescription = contentDescription }
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier
                .width(36.dp)
                .heightIn(min = 34.dp),
            shape = RoundedCornerShape(9.dp),
            color = MaterialTheme.colorScheme.surfaceContainer,
            contentColor = if (enabled) tint else tint.copy(alpha = tint.alpha * 0.38f),
        ) {
            Box(contentAlignment = Alignment.Center) { content() }
        }
    }
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
private fun MarkCard(subject: Subject, mark: Mark) {
    val date = parseMarkDate(mark.markDate)
    val metadata = MarkCardMetadataPolicy.resolve(
        mark = mark,
        resolvedWeight = GradeMath.resolvedWeight(mark, subject),
        untitledCaption = stringResource(R.string.mark_untitled),
    )

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 112.dp),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(1.dp),
            ) {
                Text(
                    text = metadata.caption,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = 18.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                metadata.theme?.let { theme ->
                    Text(
                        text = theme,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 17.sp,
                        lineHeight = 20.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = relativeDate(date),
                        color = AccentTeal,
                        fontSize = 13.sp,
                        lineHeight = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    date?.let {
                        Spacer(Modifier.width(8.dp))
                        Text(
                            text = it.fullDate(),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 13.sp,
                            lineHeight = 17.sp,
                        )
                    }
                }
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    metadata.typeLabel?.let {
                        TagPill(
                            text = it,
                            color = MaterialTheme.colorScheme.surfaceVariant,
                            textColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    metadata.weightBadge?.let { weight ->
                        val label = when (weight.kind) {
                            MarkWeightBadgeKind.EXPLICIT -> R.string.mark_weight
                            MarkWeightBadgeKind.ESTIMATED -> R.string.mark_weight_estimated
                        }
                        TagPill(
                            text = stringResource(label, GradeMath.formattedWeight(weight.value)),
                            color = SoftMint,
                            textColor = ExcellentGreen,
                        )
                    }
                    metadata.pointsLabel?.let {
                        TagPill(text = it, color = SoftTeal, textColor = AccentTeal)
                    }
                    if (metadata.isNew) {
                        TagPill(
                            text = stringResource(R.string.mark_new),
                            color = Color(0xFFFFF0D7),
                            textColor = WarningOrange,
                        )
                    }
                }
            }
            GradeyGradeBadge(
                text = mark.markText,
                band = GradeMath.band(mark),
            )
        }
    }
}

@Composable
private fun EmptyMarksCard() {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(80.dp),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 1.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                stringResource(R.string.subject_no_marks),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 15.sp,
            )
        }
    }
}

@Composable
private fun InlineMarkPill(mark: Mark) {
    val (background, foreground) = mark.gradeColors()
    Surface(
        modifier = Modifier.height(23.dp),
        shape = RoundedCornerShape(12.dp),
        color = background,
    ) {
        Box(
            modifier = Modifier.padding(horizontal = 10.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = mark.markText,
                color = foreground,
                fontSize = 14.sp,
                lineHeight = 17.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun TagPill(text: String, color: Color, textColor: Color) {
    Surface(
        modifier = Modifier.height(23.dp),
        shape = RoundedCornerShape(12.dp),
        color = color,
    ) {
        Box(
            modifier = Modifier.padding(horizontal = 10.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = text,
                color = textColor,
                fontSize = 13.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun StatusBarAppearance(
    useDarkIcons: Boolean,
    restoreDarkIcons: Boolean,
) {
    val view = LocalView.current
    val activity = view.context as? Activity
    if (activity != null && !view.isInEditMode) {
        SideEffect {
            WindowCompat.getInsetsController(activity.window, view).isAppearanceLightStatusBars = useDarkIcons
        }
        DisposableEffect(activity, view, restoreDarkIcons) {
            onDispose {
                WindowCompat.getInsetsController(activity.window, view).isAppearanceLightStatusBars = restoreDarkIcons
            }
        }
    }
}

private fun Mark.gradeColors(): Pair<Color, Color> = GradeMath.band(this).subjectColors()

private fun GradeBand.subjectColors(): Pair<Color, Color> = softColor() to color()

private fun parseMarkDate(raw: String?): LocalDate? {
    return MarkDateParser.localDate(raw, PragueZone)
}

@Composable
private fun relativeDate(date: LocalDate?): String {
    date ?: return stringResource(R.string.mark_date_unavailable)
    val days = ChronoUnit.DAYS.between(date, LocalDate.now(PragueZone)).coerceAtLeast(0)
    return when {
        days == 0L -> stringResource(R.string.mark_date_today)
        days == 1L -> stringResource(R.string.mark_date_yesterday)
        days < 7L -> relativeQuantity(R.plurals.mark_date_days_ago, days)
        days < 30L -> relativeQuantity(R.plurals.mark_date_weeks_ago, days / 7)
        days < 60L -> relativeQuantity(R.plurals.mark_date_months_ago, 1)
        days < 365L -> relativeQuantity(R.plurals.mark_date_months_ago, days / 30)
        else -> relativeQuantity(R.plurals.mark_date_years_ago, days / 365)
    }
}

@Composable
private fun relativeQuantity(resource: Int, count: Long): String {
    val safeCount = count.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    return pluralStringResource(resource, safeCount, safeCount)
}

private fun LocalDate.shortDate(): String = "$dayOfMonth. $monthValue."

private fun LocalDate.fullDate(): String = "$dayOfMonth. $monthValue. $year"

private fun String.subjectKey(): String = Normalizer.normalize(this, Normalizer.Form.NFD)
    .replace(Regex("\\p{M}+"), "")
    .lowercase(Locale.ROOT)
    .replace(Regex("[^a-z0-9]+"), "")

private fun formatAverage(average: Double?): String =
    GradeMath.formattedAverage(average).replace('.', ',')

private fun formatOneDecimal(value: Double): String =
    String.format(Locale.US, "%.1f", value).replace('.', ',')
