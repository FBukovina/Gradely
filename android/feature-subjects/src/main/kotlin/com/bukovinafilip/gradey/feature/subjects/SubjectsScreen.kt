package com.bukovinafilip.gradey.feature.subjects

import android.app.Activity
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Verified
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
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
import com.bukovinafilip.gradey.domain.GradeBand
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.domain.MarkCardMetadataPolicy
import com.bukovinafilip.gradey.domain.MarkDateParser
import com.bukovinafilip.gradey.domain.MarkPredictionInput
import com.bukovinafilip.gradey.domain.MarkWeightBadgeKind
import com.bukovinafilip.gradey.domain.SubjectDirectorySearch
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.Subject
import java.text.Collator
import java.text.Normalizer
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.roundToInt

private val BackgroundTop = Color(0xFFCBDDDD)
private val BackgroundBottom = Color(0xFFEFEFF4)
private val AccentTeal = Color(0xFF17A185)
private val HeroStart = Color(0xFF18A182)
private val HeroEnd = Color(0xFF1CA567)
private val DetailHeroStart = Color(0xFF148A94)
private val DetailHeroEnd = Color(0xFF3099A1)
private val CardWhite = Color(0xFFFDFDFE)
private val MutedText = Color(0xFF8E8E93)
private val DividerColor = Color(0xFFC6C6C8)
private val SoftTeal = Color(0xFFDEEFF0)
private val SoftMint = Color(0xFFE0F3EA)
private val SoftGray = Color(0xFFEEEEF0)
private val ExcellentGreen = Color(0xFF18A56F)
private val WarningOrange = Color(0xFFE0921A)
private val DangerRed = Color(0xFFD95461)
private val PragueZone = ZoneId.of("Europe/Prague")

private enum class SubjectSortMode(val label: String) {
    Focus("Focus"),
    Average("Average"),
    Alphabetical("A-Z"),
}

@Composable
fun SubjectsScreen(
    subjects: List<Subject>,
    absence: AbsenceResponse,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedSubjectID by rememberSaveable { mutableStateOf<String?>(null) }
    var sortMode by remember { mutableStateOf(SubjectSortMode.Focus) }
    var searchQuery by rememberSaveable { mutableStateOf("") }
    val selectedSubject = subjects.firstOrNull { it.id == selectedSubjectID }

    LaunchedEffect(selectedSubjectID, subjects) {
        if (selectedSubjectID != null && selectedSubject == null) selectedSubjectID = null
    }
    BackHandler(enabled = selectedSubject != null) { selectedSubjectID = null }

    if (selectedSubject == null) {
        SubjectsOverview(
            subjects = subjects,
            absence = absence,
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
            onBack = { selectedSubjectID = null },
            modifier = modifier,
        )
    }
}

@Composable
private fun SubjectsOverview(
    subjects: List<Subject>,
    absence: AbsenceResponse,
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
    val sortedSubjects = remember(filteredSubjects, absenceRows, sortMode) {
        when (sortMode) {
            SubjectSortMode.Focus -> filteredSubjects.sortedWith(
                compareByDescending<Subject> {
                    val average = GradeMath.subjectAverage(it) ?: -1.0
                    val absencePercentage = absenceRows[it.displayName.subjectKey()]?.absencePercentage ?: 0.0
                    average + absencePercentage / 100.0
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
            .background(BackgroundBottom),
    ) {
        MarksBackgroundGlow()
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, top = 13.dp, end = 16.dp, bottom = 126.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                MarksHeader(
                    title = "Marks",
                    isRefreshing = isRefreshing,
                    onRefresh = onRefresh,
                    onOpenAccount = onOpenAccount,
                    onOpenGradeyTools = onOpenGradeyTools,
                )
            }
            item { OverallAverageCard(subjects) }
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
                        emptyMessage = if (searchQuery.isBlank()) {
                            "No subjects available"
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
            Icon(Icons.Default.Search, contentDescription = null)
        },
        trailingIcon = if (query.isNotEmpty()) {
            {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(Icons.Default.Close, contentDescription = stringResource(R.string.marks_search_clear))
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
                Surface(
                    modifier = Modifier.size(30.dp),
                    shape = CircleShape,
                    color = Color(0xFFC7ECE9),
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
            text = title,
            color = Color.Black,
            fontSize = 18.sp,
            lineHeight = 22.sp,
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
                                contentDescription = "Refresh Marks",
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
private fun OverallAverageCard(subjects: List<Subject>) {
    val overallAverage = formatAverage(GradeMath.overallAverage(subjects))
    val totalMarks = subjects.sumOf { it.marks.size }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(124.dp),
        shape = RoundedCornerShape(20.dp),
        color = Color.Transparent,
        shadowElevation = 2.dp,
    ) {
        Row(
            modifier = Modifier
                .background(Brush.horizontalGradient(listOf(HeroStart, HeroEnd)))
                .padding(horizontal = 24.dp, vertical = 20.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Column {
                Text(
                    text = "Overall average",
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
                    text = "${subjects.size} ${plural(subjects.size, "subject", "subjects")}",
                    color = Color(0xFF073C35),
                    fontSize = 14.sp,
                    lineHeight = 18.sp,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    text = "$totalMarks ${plural(totalMarks, "mark", "marks")}",
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
private fun SubjectsSectionHeader(
    sortMode: SubjectSortMode,
    onSortModeChange: (SubjectSortMode) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(31.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        SectionHeading("SUBJECTS")
        Surface(
            modifier = Modifier
                .width(173.dp)
                .height(31.dp),
            shape = RoundedCornerShape(16.dp),
            color = Color(0xFFD7E4E4).copy(alpha = 0.92f),
        ) {
            Row(modifier = Modifier.padding(1.dp)) {
                SortSegment(
                    modifier = Modifier.width(55.dp),
                    mode = SubjectSortMode.Focus,
                    selected = sortMode == SubjectSortMode.Focus,
                    onClick = { onSortModeChange(SubjectSortMode.Focus) },
                )
                SortSegment(
                    modifier = Modifier.width(73.dp),
                    mode = SubjectSortMode.Average,
                    selected = sortMode == SubjectSortMode.Average,
                    onClick = { onSortModeChange(SubjectSortMode.Average) },
                )
                SortSegment(
                    modifier = Modifier.width(43.dp),
                    mode = SubjectSortMode.Alphabetical,
                    selected = sortMode == SubjectSortMode.Alphabetical,
                    onClick = { onSortModeChange(SubjectSortMode.Alphabetical) },
                )
            }
        }
    }
}

@Composable
private fun SortSegment(
    modifier: Modifier,
    mode: SubjectSortMode,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Surface(
        modifier = modifier.height(29.dp),
        onClick = onClick,
        shape = RoundedCornerShape(15.dp),
        color = if (selected) Color.White else Color.Transparent,
        shadowElevation = if (selected) 1.dp else 0.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = mode.label,
                color = Color.Black,
                fontSize = 14.sp,
                lineHeight = 17.sp,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun SubjectsCard(
    subjects: List<Subject>,
    absenceByName: Map<String, com.bukovinafilip.gradey.domain.AbsenceSubjectSummary>,
    emptyMessage: String,
    onOpenSubject: (Subject) -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = CardWhite,
        shadowElevation = 1.dp,
    ) {
        if (subjects.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(68.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(emptyMessage, color = MutedText, fontSize = 14.sp)
            }
        } else {
            Column {
                subjects.forEachIndexed { index, subject ->
                    SubjectRow(
                        subject = subject,
                        absencePercentage = absenceByName[subject.displayName.subjectKey()]?.absencePercentage,
                        onClick = { onOpenSubject(subject) },
                    )
                    if (index != subjects.lastIndex) {
                        HorizontalDivider(
                            modifier = Modifier.padding(start = 68.dp),
                            thickness = 0.5.dp,
                            color = DividerColor.copy(alpha = 0.72f),
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
    onClick: () -> Unit,
) {
    val average = GradeMath.subjectAverage(subject)
    val latestMark = subject.marks.maxByOrNull { it.markDate.orEmpty() }

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
            color = SoftTeal,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    text = subject.subjectInfo.abbrev.ifBlank { subject.displayName.take(2) },
                    color = Color(0xFF108A94),
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
                color = Color.Black,
                fontSize = 18.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.Bold,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                val markCount = subject.marks.size
                Text(
                    text = "$markCount ${plural(markCount, "mark", "marks")}",
                    color = MutedText,
                    fontSize = 16.sp,
                    lineHeight = 19.sp,
                )
                latestMark?.let {
                    Spacer(Modifier.width(8.dp))
                    GradePill(mark = it, compact = true)
                }
            }
        }
        Column(
            modifier = Modifier.width(80.dp),
            horizontalAlignment = Alignment.End,
        ) {
            Text(
                text = formatAverage(average),
                color = Color(0xFF108A94),
                fontSize = 20.sp,
                lineHeight = 23.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = absencePercentage?.let { "${it.roundToInt()}% absent" } ?: "— absent",
                color = MutedText,
                fontSize = 14.sp,
                lineHeight = 17.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
        }
        Spacer(Modifier.width(4.dp))
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = "Open ${subject.displayName}",
            tint = Color(0xFFC7C7CC),
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun SubjectDetail(
    subject: Subject,
    absence: AbsenceResponse,
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
    val trialValue = remember(trialMark) { MarkPredictionInput.markValue(trialMark) }
    val trialMarkError = if (MarkPredictionInput.isInvalid(trialMark)) {
        stringResource(R.string.mark_prediction_invalid)
    } else {
        null
    }
    val average = remember(subject, trialValue, trialWeight) {
        trialValue?.let {
            GradeMath.theoreticalAverage(
                existingMarks = subject.marks,
                subjectAverageText = subject.averageText,
                markValue = it,
                weight = trialWeight,
            )
        } ?: GradeMath.subjectAverage(subject)
    }

    StatusBarAppearance(useDarkIcons = !isScrolled)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(BackgroundBottom),
    ) {
        MarksBackgroundGlow()
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            contentPadding = PaddingValues(start = 16.dp, top = 117.dp, end = 16.dp, bottom = 126.dp),
        ) {
            item {
                SubjectAverageHero(
                    average = average,
                    predicted = trialValue != null,
                    markCount = subject.marks.size,
                    absencePercentage = absenceRow?.absencePercentage,
                )
            }
            item { Spacer(Modifier.height(16.dp)) }
            item { SectionHeading("AVERAGE OVER TIME") }
            item { Spacer(Modifier.height(18.dp)) }
            item { AverageChartCard(subject) }
            item { Spacer(Modifier.height(10.dp)) }
            item { SectionHeading("TRY A MARK") }
            item { Spacer(Modifier.height(24.dp)) }
            item {
                TryMarkCard(
                    value = trialMark,
                    weight = trialWeight,
                    enabled = subject.markPredictionEnabled && !subject.pointsOnly,
                    errorMessage = trialMarkError,
                    onValueChange = { trialMark = MarkPredictionInput.acceptedMarkText(trialMark, it) },
                    onDecreaseWeight = { trialWeight = MarkPredictionInput.decreaseWeight(trialWeight) },
                    onIncreaseWeight = { trialWeight = MarkPredictionInput.increaseWeight(trialWeight) },
                )
            }
            item { Spacer(Modifier.height(8.dp)) }
            item { SectionHeading("MARKS") }
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
            color = if (isScrolled) Color(0xFFA3E3E6) else Color(0xFFE9FCFB),
            shadowElevation = 2.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Default.ChevronLeft,
                    contentDescription = "Back",
                    tint = Color(0xFF061C1B),
                    modifier = Modifier.size(28.dp),
                )
            }
        }
        Text(
            text = title,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            color = if (isScrolled) Color.White else Color.Black,
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
        shape = RoundedCornerShape(20.dp),
        color = Color.Transparent,
        shadowElevation = 2.dp,
    ) {
        Column(
            modifier = Modifier
                .background(Brush.horizontalGradient(listOf(DetailHeroStart, DetailHeroEnd)))
                .padding(top = 24.dp, bottom = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = if (predicted) "Predicted average" else "Average",
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
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                DetailChip(
                    icon = { Icon(Icons.Default.Verified, contentDescription = null, modifier = Modifier.size(14.dp)) },
                    text = "$markCount ${plural(markCount, "mark", "marks")}",
                )
                DetailChip(
                    icon = { Icon(Icons.Default.CalendarMonth, contentDescription = null, modifier = Modifier.size(14.dp)) },
                    text = absencePercentage?.let { "Absence ${formatOneDecimal(it)} %" } ?: "Absence —",
                )
            }
        }
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

private data class AveragePoint(
    val date: LocalDate?,
    val average: Double,
)

@Composable
private fun AverageChartCard(subject: Subject) {
    val points = remember(subject) { subject.averagePoints() }
    val fallbackAverage = GradeMath.subjectAverage(subject) ?: 3.0
    val values = points.map(AveragePoint::average).ifEmpty { listOf(fallbackAverage) }
    val topValue = ((values.minOrNull()!! * 10.0).roundToInt() - 1) / 10.0
    val bottomValue = ((values.maxOrNull()!! * 10.0).roundToInt() + 1) / 10.0
    val safeBottomValue = if (bottomValue <= topValue) topValue + 0.2 else bottomValue
    val firstDate = points.firstOrNull()?.date
    val firstLabel = firstDate?.minusDays(1)?.shortDate() ?: "—"
    val secondLabel = firstDate?.plusDays(1)?.shortDate() ?: "—"

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(237.dp)
            .semantics {
                contentDescription = "Average over time, ${points.size} ${plural(points.size, "point", "points")}"
            },
        shape = RoundedCornerShape(20.dp),
        color = CardWhite,
        shadowElevation = 1.dp,
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val xStart = 16.dp.toPx()
                val xEnd = size.width - 36.dp.toPx()
                val yTop = 51.dp.toPx()
                val yBottom = 114.dp.toPx()
                drawLine(Color(0xFFE6E6E8), Offset(xStart, yTop), Offset(xEnd, yTop), strokeWidth = 0.7.dp.toPx())
                drawLine(Color(0xFFE6E6E8), Offset(xStart, yBottom), Offset(xEnd, yBottom), strokeWidth = 0.7.dp.toPx())

                val drawablePoints = if (points.isEmpty()) listOf(AveragePoint(null, fallbackAverage)) else points
                val offsets = drawablePoints.mapIndexed { index, point ->
                    val x = if (drawablePoints.size == 1) {
                        (xStart + xEnd) / 2f
                    } else {
                        xStart + (xEnd - xStart) * index.toFloat() / drawablePoints.lastIndex.toFloat()
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
                    drawCircle(Color.White, radius = 6.dp.toPx(), center = point)
                    drawCircle(Color(0xFF1396A0), radius = 4.5.dp.toPx(), center = point)
                }
            }

            Text(
                text = formatOneDecimal(topValue),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 44.dp, end = 16.dp),
                color = MutedText,
                fontSize = 13.sp,
                lineHeight = 17.sp,
            )
            Text(
                text = formatOneDecimal(safeBottomValue),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 107.dp, end = 16.dp),
                color = MutedText,
                fontSize = 13.sp,
                lineHeight = 17.sp,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .offset(y = 170.dp)
                    .padding(start = 54.dp),
            ) {
                listOf(firstLabel, secondLabel, "...").forEach { label ->
                    Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        Text(label, color = MutedText, fontSize = 13.sp, lineHeight = 17.sp)
                    }
                }
            }
            Text(
                text = "Computed from marks",
                modifier = Modifier.offset(x = 16.dp, y = 194.dp),
                color = MutedText,
                fontSize = 13.sp,
                lineHeight = 17.sp,
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
    onValueChange: (String) -> Unit,
    onDecreaseWeight: () -> Unit,
    onIncreaseWeight: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(if (errorMessage == null) 138.dp else 158.dp),
        shape = RoundedCornerShape(20.dp),
        color = CardWhite,
        shadowElevation = 1.dp,
    ) {
        Column(modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp)) {
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                enabled = enabled,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(46.dp)
                    .background(SoftGray, RoundedCornerShape(13.dp))
                    .padding(horizontal = 13.dp),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                cursorBrush = SolidColor(AccentTeal),
                textStyle = TextStyle(
                    color = Color.Black,
                    fontSize = 18.sp,
                    lineHeight = 22.sp,
                ),
                decorationBox = { field ->
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) {
                        if (value.isEmpty()) {
                            Text(
                                text = if (enabled) "Mark, e.g. 2+" else "Prediction unavailable",
                                color = Color(0xFFC4C4C8),
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
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .background(SoftGray, RoundedCornerShape(13.dp))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                StepperButton(
                    enabled = enabled && weight > 1,
                    onClick = onDecreaseWeight,
                    contentDescription = "Decrease weight",
                    tint = Color(0xFFD1D1D6),
                ) {
                    Icon(Icons.Default.Remove, contentDescription = null, modifier = Modifier.size(22.dp))
                }
                Text(
                    text = "Weight $weight",
                    color = Color.Black,
                    fontSize = 17.sp,
                    lineHeight = 21.sp,
                    fontWeight = FontWeight.Bold,
                )
                StepperButton(
                    enabled = enabled && weight < 10,
                    onClick = onIncreaseWeight,
                    contentDescription = "Increase weight",
                    tint = AccentTeal,
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(27.dp))
                }
            }
        }
    }
}

@Composable
private fun StepperButton(
    enabled: Boolean,
    onClick: () -> Unit,
    contentDescription: String,
    tint: Color,
    content: @Composable () -> Unit,
) {
    Surface(
        modifier = Modifier
            .width(36.dp)
            .height(34.dp)
            .semantics { this.contentDescription = contentDescription },
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(9.dp),
        color = Color.White.copy(alpha = if (enabled) 0.96f else 0.64f),
        contentColor = tint,
    ) {
        Box(contentAlignment = Alignment.Center) { content() }
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
        color = CardWhite,
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
                    color = Color.Black,
                    fontSize = 18.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                metadata.theme?.let { theme ->
                    Text(
                        text = theme,
                        color = MutedText,
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
                            color = MutedText,
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
                        TagPill(text = it, color = Color(0xFFF0F0F2), textColor = MutedText)
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
            GradePill(mark = mark, compact = false)
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
        color = CardWhite,
        shadowElevation = 1.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text("No marks yet", color = MutedText, fontSize = 15.sp)
        }
    }
}

@Composable
private fun GradePill(mark: Mark, compact: Boolean) {
    val (background, foreground) = mark.gradeColors()
    Surface(
        modifier = if (compact) Modifier.height(23.dp) else Modifier.size(width = 76.dp, height = 39.dp),
        shape = RoundedCornerShape(if (compact) 12.dp else 16.dp),
        color = background,
    ) {
        Box(
            modifier = if (compact) Modifier.padding(horizontal = 10.dp) else Modifier,
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = mark.markText,
                color = foreground,
                fontSize = if (compact) 14.sp else 22.sp,
                lineHeight = if (compact) 17.sp else 26.sp,
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
private fun SectionHeading(text: String) {
    Text(
        text = text,
        color = MutedText,
        fontSize = 14.sp,
        lineHeight = 18.sp,
        letterSpacing = 0.7.sp,
        fontWeight = FontWeight.Bold,
    )
}

@Composable
private fun StatusBarAppearance(useDarkIcons: Boolean) {
    val view = LocalView.current
    val activity = view.context as? Activity
    if (activity != null && !view.isInEditMode) {
        SideEffect {
            WindowCompat.getInsetsController(activity.window, view).isAppearanceLightStatusBars = useDarkIcons
        }
        DisposableEffect(Unit) {
            onDispose {
                WindowCompat.getInsetsController(activity.window, view).isAppearanceLightStatusBars = true
            }
        }
    }
}

@Composable
private fun MarksBackgroundGlow() {
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

private fun Subject.averagePoints(): List<AveragePoint> {
    val ordered = marks
        .filter { GradeMath.parseMarkValue(it.markText) != null }
        .sortedWith(compareBy<Mark> { parseMarkDate(it.markDate) ?: LocalDate.MIN }.thenBy(Mark::id))
    return ordered.mapIndexedNotNull { index, mark ->
        GradeMath.weightedAverage(ordered.take(index + 1), this)?.let { average ->
            AveragePoint(parseMarkDate(mark.markDate), average)
        }
    }
}

private fun Mark.gradeColors(): Pair<Color, Color> = when (GradeMath.band(this)) {
    GradeBand.EXCELLENT -> SoftMint to ExcellentGreen
    GradeBand.GOOD -> SoftTeal to Color(0xFF108A94)
    GradeBand.AVERAGE -> Color(0xFFFFF0D7) to WarningOrange
    GradeBand.POOR -> Color(0xFFFFE5E8) to DangerRed
    GradeBand.NEUTRAL -> SoftGray to MutedText
}

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

private fun plural(count: Int, singular: String, plural: String): String =
    if (count == 1) singular else plural
