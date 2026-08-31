package com.bukovinafilip.gradey.feature.today

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
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
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import com.bukovinafilip.gradey.ui.GradeyIcons
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.domain.AbsenceRiskLevel
import com.bukovinafilip.gradey.domain.AbsenceRiskSummary
import com.bukovinafilip.gradey.domain.GradeHistoryTrends
import com.bukovinafilip.gradey.domain.GradeMath
import com.bukovinafilip.gradey.domain.GradeTrendRange
import com.bukovinafilip.gradey.domain.SchoolLoginValidator
import com.bukovinafilip.gradey.domain.SchoolReconnectPrefill
import com.bukovinafilip.gradey.domain.SubjectGradeTrend
import com.bukovinafilip.gradey.domain.TodayMealState
import com.bukovinafilip.gradey.domain.TodayLinkedAccounts
import com.bukovinafilip.gradey.domain.TodayLinkedAccountSummary
import com.bukovinafilip.gradey.domain.TodayMeals
import com.bukovinafilip.gradey.domain.TodayNewMark
import com.bukovinafilip.gradey.domain.TodayNewMarks
import com.bukovinafilip.gradey.domain.TodayPresentationState
import com.bukovinafilip.gradey.domain.TodayStudentNames
import com.bukovinafilip.gradey.domain.TodayTimetableState
import com.bukovinafilip.gradey.domain.TodayTimetableSummaries
import com.bukovinafilip.gradey.domain.TodayTimetableSummary
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.NewMarkEvent
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.ui.GradeyAbsenceRiskRing
import com.bukovinafilip.gradey.ui.GradeyCardTokens
import com.bukovinafilip.gradey.ui.GradeyColors
import com.bukovinafilip.gradey.ui.GradeyAuroraBackground
import com.bukovinafilip.gradey.ui.GradeySectionHeader
import com.bukovinafilip.gradey.ui.gradeyBrandGradient
import com.bukovinafilip.gradey.ui.riskColor
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

private val WarningOrange = Color(0xFFFF8D28)
private val DangerRed = Color(0xFFE5545D)
private val PragueZone = ZoneId.of("Europe/Prague")

internal const val TODAY_TRENDS_BACK_TEST_TAG = "todayTrendsBack"
internal const val TODAY_RANGE_TEST_TAG_PREFIX = "todayTrendRange:"
internal const val TODAY_ACTION_PILL_VISUAL_TEST_TAG = "todayActionPillVisual"
internal const val TODAY_ABSENCE_PREDICTOR_CARD_TEST_TAG = "todayAbsencePredictorCard"
internal const val TODAY_ABSENCE_PREDICTOR_ACTION_TEST_TAG = "todayAbsencePredictorAction"

@Composable
fun TodayStateScreen(
    state: TodayPresentationState,
    errorMessage: String?,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        GradeyAuroraBackground()
        Column(
            modifier = Modifier
                .widthIn(max = 520.dp)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = stringResource(R.string.today_title),
                color = MaterialTheme.colorScheme.onBackground,
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
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                        Text(
                            text = stringResource(R.string.today_loading),
                            color = MaterialTheme.colorScheme.onSurface,
                            fontSize = 18.sp,
                            lineHeight = 23.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = stringResource(R.string.today_loading_subtitle),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    } else {
                        Icon(
                            imageVector = GradeyIcons.Calendar,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(34.dp),
                        )
                        Text(
                            text = if (errorMessage == null) {
                                stringResource(R.string.today_no_data)
                            } else {
                                stringResource(R.string.today_load_failed)
                            },
                            color = MaterialTheme.colorScheme.onSurface,
                            fontSize = 18.sp,
                            lineHeight = 23.sp,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            text = errorMessage ?: stringResource(R.string.today_no_data_subtitle),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                        Button(
                            onClick = onRetry,
                            modifier = Modifier.heightIn(min = 48.dp),
                        ) {
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
    activeLinkedAccountDisplayName: String? = null,
    linkedSchoolAccounts: List<LinkedSchoolAccount> = emptyList(),
    activeLinkedAccountID: String? = null,
    mutatingLinkedAccountID: String? = null,
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
    onActivateLinkedAccount: (LinkedSchoolAccount) -> Unit,
    onReconnectPrefill: suspend (LinkedSchoolAccount) -> SchoolReconnectPrefill?,
    onReconnectLinkedAccount: suspend (LinkedSchoolAccount, String, String, String) -> String?,
    modifier: Modifier = Modifier,
) {
    var showsTrendDetails by rememberSaveable { mutableStateOf(false) }
    var selectedTrendRangeName by rememberSaveable { mutableStateOf(GradeTrendRange.NINETY_DAYS.name) }
    var reconnectSheet by remember { mutableStateOf<TodayReconnectSheetState?>(null) }
    var reconnectRequest by remember { mutableIntStateOf(0) }
    val reconnectScope = rememberCoroutineScope()
    val todayListState = rememberLazyListState()
    val subjects = dashboard.marksResponse.subjects
    val overall = GradeMath.formattedAverage(GradeMath.overallAverage(subjects))
    val totalMarks = subjects.sumOf { it.marks.size }
    val studentName = TodayStudentNames.resolve(
        schoolFullName = dashboard.user?.fullName,
        activeLinkedAccountDisplayName = activeLinkedAccountDisplayName,
    ) ?: stringResource(R.string.today_gradey)
    val linkedAccountSummary = remember(linkedSchoolAccounts, activeLinkedAccountID) {
        TodayLinkedAccounts.resolve(linkedSchoolAccounts, activeLinkedAccountID)
    }
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

    fun showReconnect(account: LinkedSchoolAccount) {
        reconnectRequest += 1
        val request = reconnectRequest
        reconnectScope.launch {
            val prefill = try {
                onReconnectPrefill(account)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                null
            }
            if (request == reconnectRequest) {
                reconnectSheet = TodayReconnectSheetState(account = account, prefill = prefill)
            }
        }
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
            .fillMaxSize(),
    ) {
        GradeyAuroraBackground()
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
            if (linkedAccountSummary.schoolAccounts.isNotEmpty()) {
                item {
                    LinkedSchoolAccountPicker(
                        summary = linkedAccountSummary,
                        mutatingLinkedAccountID = mutatingLinkedAccountID,
                        onActivate = onActivateLinkedAccount,
                        onReconnect = ::showReconnect,
                    )
                }
            }
            linkedAccountSummary.accountRequiringReconnect?.let { linked ->
                item {
                    SchoolConnectionNotice(
                        account = linked,
                        isBusy = mutatingLinkedAccountID != null,
                        onReconnect = { showReconnect(linked) },
                    )
                }
            }
            item {
                AverageCard(
                    fullName = studentName,
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

    reconnectSheet?.let { sheet ->
        TodaySchoolReconnectSheet(
            account = sheet.account,
            prefill = sheet.prefill,
            onReconnect = { school, username, password ->
                onReconnectLinkedAccount(sheet.account, school, username, password)
            },
            onDismiss = { reconnectSheet = null },
        )
    }
}

private data class TodayReconnectSheetState(
    val account: LinkedSchoolAccount,
    val prefill: SchoolReconnectPrefill?,
)

@Composable
private fun LinkedSchoolAccountPicker(
    summary: TodayLinkedAccountSummary,
    mutatingLinkedAccountID: String?,
    onActivate: (LinkedSchoolAccount) -> Unit,
    onReconnect: (LinkedSchoolAccount) -> Unit,
) {
    var isExpanded by remember { mutableStateOf(false) }
    val active = summary.activeAccount
    DashboardSurface {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconTile(background = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)) {
                Icon(
                    imageVector = GradeyIcons.User,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(22.dp),
                )
            }
            Spacer(Modifier.width(13.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = active?.displayName ?: stringResource(R.string.today_school_account),
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = 16.sp,
                    lineHeight = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = active?.schoolName ?: stringResource(R.string.today_linked_accounts),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Box {
                if (mutatingLinkedAccountID != null) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = MaterialTheme.colorScheme.primary,
                        strokeWidth = 2.dp,
                    )
                } else {
                    IconButton(onClick = { isExpanded = true }) {
                        Icon(
                            imageVector = GradeyIcons.ArrowDown,
                            contentDescription = stringResource(R.string.today_choose_school_account),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
                DropdownMenu(
                    expanded = isExpanded,
                    onDismissRequest = { isExpanded = false },
                ) {
                    summary.schoolAccounts.forEach { linked ->
                        val canActivate = linked.status == LinkedAccountStatus.ACTIVE && linked.id != active?.id
                        val canReconnect = linked.status == LinkedAccountStatus.ACTION_REQUIRED ||
                            linked.status == LinkedAccountStatus.FAILED
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(linked.displayName, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        text = linked.schoolName ?: linked.status.localizedLabel(),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        fontSize = 12.sp,
                                    )
                                }
                            },
                            enabled = canActivate || canReconnect,
                            onClick = {
                                isExpanded = false
                                if (canReconnect) {
                                    onReconnect(linked)
                                } else if (canActivate) {
                                    onActivate(linked)
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SchoolConnectionNotice(
    account: LinkedSchoolAccount,
    isBusy: Boolean,
    onReconnect: () -> Unit,
) {
    DashboardSurface {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = GradeyIcons.Alert,
                    contentDescription = null,
                    tint = WarningOrange,
                    modifier = Modifier.size(22.dp),
                )
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = stringResource(R.string.today_school_attention),
                        color = MaterialTheme.colorScheme.onSurface,
                        fontSize = 15.sp,
                        lineHeight = 19.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = account.displayName,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                    )
                }
            }
            Text(
                text = stringResource(R.string.today_reconnect_fallback),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp,
                lineHeight = 18.sp,
            )
            Button(
                modifier = Modifier.fillMaxWidth(),
                enabled = !isBusy,
                onClick = onReconnect,
            ) {
                Text(stringResource(R.string.today_reconnect))
            }
        }
    }
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun TodaySchoolReconnectSheet(
    account: LinkedSchoolAccount,
    prefill: SchoolReconnectPrefill?,
    onReconnect: suspend (String, String, String) -> String?,
    onDismiss: () -> Unit,
) {
    var school by remember(account.id, prefill) { mutableStateOf(prefill?.schoolURL.orEmpty()) }
    var username by remember(account.id, prefill) { mutableStateOf(prefill?.username.orEmpty()) }
    var password by remember(account.id) { mutableStateOf("") }
    var isPasswordVisible by remember(account.id) { mutableStateOf(false) }
    var hasAttempted by remember(account.id) { mutableStateOf(false) }
    var isSubmitting by remember(account.id) { mutableStateOf(false) }
    var errorMessage by remember(account.id) { mutableStateOf<String?>(null) }
    val focusManager = LocalFocusManager.current
    val scope = rememberCoroutineScope()
    val validation = remember(school, username, password) {
        SchoolLoginValidator.validate(school, username, password)
    }
    val genericError = stringResource(R.string.today_reconnect_failed)

    fun submit() {
        hasAttempted = true
        if (!validation.isValid || isSubmitting) return
        focusManager.clearFocus()
        scope.launch {
            isSubmitting = true
            errorMessage = null
            try {
                val error = onReconnect(school, username, password)
                if (error == null) onDismiss() else errorMessage = error
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                errorMessage = genericError
            } finally {
                isSubmitting = false
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = { if (!isSubmitting) onDismiss() },
        shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        dragHandle = null,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 680.dp)
                .verticalScroll(rememberScrollState())
                .padding(start = 24.dp, top = 28.dp, end = 24.dp, bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = stringResource(
                    R.string.today_reconnect_title,
                    prefill?.schoolName?.takeIf(String::isNotBlank) ?: account.displayName,
                ),
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 22.sp,
                lineHeight = 28.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = stringResource(R.string.today_reconnect_message),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 14.sp,
                lineHeight = 20.sp,
            )
            OutlinedTextField(
                modifier = Modifier.fillMaxWidth(),
                value = school,
                onValueChange = {
                    school = it
                    errorMessage = null
                },
                label = { Text(stringResource(R.string.today_school_url)) },
                singleLine = true,
                enabled = !isSubmitting,
                isError = hasAttempted && validation.schoolURLError != null,
                supportingText = if (hasAttempted && validation.schoolURLError != null) {
                    {
                        Text(
                            stringResource(
                                if (school.isBlank()) {
                                    R.string.today_school_url_required
                                } else {
                                    R.string.today_school_url_invalid
                                },
                            ),
                        )
                    }
                } else {
                    null
                },
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    keyboardType = KeyboardType.Uri,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(
                    onNext = { focusManager.moveFocus(FocusDirection.Down) },
                ),
            )
            OutlinedTextField(
                modifier = Modifier.fillMaxWidth(),
                value = username,
                onValueChange = {
                    username = it
                    errorMessage = null
                },
                label = { Text(stringResource(R.string.today_username)) },
                singleLine = true,
                enabled = !isSubmitting,
                isError = hasAttempted && validation.usernameError != null,
                supportingText = if (hasAttempted && validation.usernameError != null) {
                    { Text(stringResource(R.string.today_username_required)) }
                } else {
                    null
                },
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    keyboardType = KeyboardType.Text,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(
                    onNext = { focusManager.moveFocus(FocusDirection.Down) },
                ),
            )
            OutlinedTextField(
                modifier = Modifier.fillMaxWidth(),
                value = password,
                onValueChange = {
                    password = it
                    errorMessage = null
                },
                label = { Text(stringResource(R.string.today_password)) },
                singleLine = true,
                enabled = !isSubmitting,
                isError = hasAttempted && validation.passwordError != null,
                supportingText = if (hasAttempted && validation.passwordError != null) {
                    { Text(stringResource(R.string.today_password_required)) }
                } else {
                    null
                },
                visualTransformation = if (isPasswordVisible) {
                    VisualTransformation.None
                } else {
                    PasswordVisualTransformation()
                },
                trailingIcon = {
                    IconButton(
                        enabled = !isSubmitting,
                        onClick = { isPasswordVisible = !isPasswordVisible },
                    ) {
                        Icon(
                            imageVector = if (isPasswordVisible) GradeyIcons.ViewOff else GradeyIcons.View,
                            contentDescription = stringResource(
                                if (isPasswordVisible) R.string.today_hide_password else R.string.today_show_password,
                            ),
                        )
                    }
                },
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { submit() }),
            )
            errorMessage?.let {
                Text(
                    text = it,
                    color = DangerRed,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                )
            }
            Button(
                modifier = Modifier.fillMaxWidth(),
                enabled = !isSubmitting,
                onClick = ::submit,
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    if (isSubmitting) {
                        stringResource(R.string.today_reconnecting)
                    } else {
                        stringResource(R.string.today_reconnect)
                    },
                )
            }
        }
    }
}

@Composable
private fun LinkedAccountStatus.localizedLabel(): String = when (this) {
    LinkedAccountStatus.ACTIVE -> stringResource(R.string.today_account_active)
    LinkedAccountStatus.ACTION_REQUIRED -> stringResource(R.string.today_account_action_required)
    LinkedAccountStatus.PAUSED -> stringResource(R.string.today_account_paused)
    LinkedAccountStatus.LINKING -> stringResource(R.string.today_account_linking)
    LinkedAccountStatus.FAILED -> stringResource(R.string.today_account_failed)
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
                GradeySectionHeader(
                    text = stringResource(R.string.today_lunch),
                    modifier = Modifier
                        .weight(1f)
                        .padding(end = 8.dp),
                )
                TodayActionPill(text = stringResource(R.string.today_open), onClick = onOpenMeals)
            }
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                val mealTint = if (state is TodayMealState.Ordered) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
                IconTile(background = mealTint.copy(alpha = 0.12f)) {
                    Icon(
                        imageVector = GradeyIcons.Restaurant,
                        contentDescription = null,
                        tint = mealTint,
                        modifier = Modifier.size(22.dp),
                    )
                }
                Spacer(Modifier.width(13.dp))
                Column(modifier = Modifier.weight(1f)) {
                    val title: String
                    val subtitle: String
                    when (state) {
                        is TodayMealState.Ordered -> {
                            title = state.meal.name
                            subtitle = state.meal.typeDescription
                                .trim()
                                .takeIf(String::isNotEmpty)
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
                        color = MaterialTheme.colorScheme.onSurface,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = subtitle,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
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
    val openToolsDescription = stringResource(R.string.today_open_gradey_ai)
    val refreshDescription = stringResource(R.string.today_refresh)
    val openAccountDescription = stringResource(R.string.today_open_account)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(62.dp),
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
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
                shadowElevation = 2.dp,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Surface(
                        modifier = Modifier.size(30.dp),
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
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
            text = stringResource(R.string.today_title),
            color = MaterialTheme.colorScheme.onBackground,
            fontSize = 18.sp,
            lineHeight = 22.sp,
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
                shape = RoundedCornerShape(25.dp),
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
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
                        modifier = Modifier.size(34.dp),
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = GradeyIcons.User,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(23.dp),
                            )
                        }
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
            .heightIn(min = 166.dp),
        shape = RoundedCornerShape(20.dp),
        color = Color.Transparent,
        shadowElevation = 4.dp,
    ) {
        Column(
            modifier = Modifier
                .background(gradeyBrandGradient())
                .padding(horizontal = 24.dp, vertical = 24.dp),
        ) {
            Text(
                text = fullName,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = GradeyColors.OnAccent,
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
                        text = stringResource(R.string.today_overall_average),
                        color = GradeyColors.OnAccent.copy(alpha = 0.70f),
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = overallAverage,
                        color = GradeyColors.OnAccent,
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
                        text = pluralStringResource(
                            R.plurals.today_subject_count,
                            subjectCount,
                            subjectCount,
                        ),
                        color = GradeyColors.OnAccent.copy(alpha = 0.72f),
                        fontSize = 12.sp,
                        lineHeight = 18.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = pluralStringResource(
                            R.plurals.today_mark_count,
                            markCount,
                            markCount,
                        ),
                        color = GradeyColors.OnAccent.copy(alpha = 0.72f),
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
            IconTile(background = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)) {
                Icon(
                    imageVector = GradeyIcons.CheckmarkBadge,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(25.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.today_marks),
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = 17.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = stringResource(R.string.today_marks_subtitle),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 13.sp,
                    lineHeight = 17.sp,
                )
            }
            Icon(
                imageVector = GradeyIcons.ArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
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
                imageVector = GradeyIcons.CheckmarkBadge,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(30.dp),
            )
            Text(
                text = stringResource(R.string.today_empty_title),
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 17.sp,
                lineHeight = 22.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = stringResource(R.string.today_empty_subtitle),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
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
    val lessonFallback = stringResource(R.string.today_lesson_fallback)
    val title = when (summary.state) {
        TodayTimetableState.CURRENT -> stringResource(
            R.string.today_lesson_now,
            currentOrNext?.displayTitle(lessonFallback).orEmpty(),
        )

        TodayTimetableState.BEFORE_SCHOOL,
        TodayTimetableState.BETWEEN_LESSONS,
        -> stringResource(
            R.string.today_lesson_next,
            currentOrNext?.displayTitle(lessonFallback).orEmpty(),
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
        TodayTimetableState.CURRENT -> GradeyIcons.PlayCircle
        TodayTimetableState.BEFORE_SCHOOL,
        TodayTimetableState.BETWEEN_LESSONS,
        -> GradeyIcons.TimeSchedule

        TodayTimetableState.AFTER_SCHOOL,
        TodayTimetableState.EMPTY,
        -> GradeyIcons.CheckCircle

        TodayTimetableState.WEEKEND,
        TodayTimetableState.HOLIDAY,
        TodayTimetableState.UNAVAILABLE,
        -> GradeyIcons.Calendar
    }
    val iconTint = if (summary.state == TodayTimetableState.CURRENT) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    val iconBackground = iconTint.copy(alpha = 0.12f)

    DashboardSurface(
        modifier = Modifier.heightIn(min = 96.dp),
        onClick = onClick,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
        ) {
            GradeySectionHeader(stringResource(R.string.today_now_and_next))
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
                        color = MaterialTheme.colorScheme.onSurface,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = subtitle,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 13.sp,
                        lineHeight = 17.sp,
                    )
                }
            }
            if (summary.hasChanges) {
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 12.dp),
                    color = MaterialTheme.colorScheme.outlineVariant,
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
    val lessonFallback = stringResource(R.string.today_lesson_fallback)
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = GradeyIcons.Alert,
            contentDescription = null,
            tint = WarningOrange,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "${lesson.changeKind.localizedLabel()} · ${lesson.displayTitle(lessonFallback)}",
                color = MaterialTheme.colorScheme.onSurface,
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
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                GradeySectionHeader(
                    text = stringResource(R.string.today_absence_risk),
                    modifier = Modifier
                        .weight(1f)
                        .padding(end = 8.dp),
                )
                TodayActionPill(text = stringResource(R.string.today_open), onClick = onOpenAbsence)
            }
            Spacer(Modifier.height(5.dp))
            if (rows.isEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 24.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconTile(background = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.12f)) {
                        Icon(
                            GradeyIcons.Calendar,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Spacer(Modifier.width(13.dp))
                    Text(
                        text = stringResource(R.string.today_absence_unavailable),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 14.sp,
                    )
                }
            } else {
                rows.forEach { row ->
                    RiskRow(
                        subjectName = row.subjectName,
                        missedLessons = row.base,
                        totalLessons = row.lessonsCount,
                        percentage = row.absencePercentage,
                        threshold = row.threshold,
                        missesUntilLimit = row.missesUntilLimit,
                        level = row.level,
                    )
                }
                if (isThresholdUnavailable) {
                    Text(
                        text = stringResource(R.string.today_school_limit_unavailable),
                        modifier = Modifier.padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 6.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
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
    level: AbsenceRiskLevel,
) {
    val color = level.riskColor()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(62.dp)
            .padding(start = 6.dp, end = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        GradeyAbsenceRiskRing(
            percentage = percentage,
            threshold = threshold,
            level = level,
        )
        Spacer(Modifier.width(3.dp))
        Column(modifier = Modifier.widthIn(max = 214.dp)) {
            Text(
                text = subjectName,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 16.sp,
                lineHeight = 19.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = absenceLimitDescription(missedLessons, totalLessons, missesUntilLimit),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
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
internal fun AbsencePredictorCard(onPlanAbsence: () -> Unit) {
    DashboardSurface(
        modifier = Modifier
            .heightIn(min = 138.dp)
            .testTag(TODAY_ABSENCE_PREDICTOR_CARD_TEST_TAG),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 15.dp),
        ) {
            BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                val shouldStackHeader = LocalDensity.current.fontScale >= 1.5f || maxWidth < 300.dp
                if (shouldStackHeader) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        GradeySectionHeader(text = stringResource(R.string.today_absence_predictor))
                        TodayActionPill(
                            text = stringResource(R.string.today_plan_absence),
                            onClick = onPlanAbsence,
                            modifier = Modifier
                                .align(Alignment.End)
                                .testTag(TODAY_ABSENCE_PREDICTOR_ACTION_TEST_TAG),
                        )
                    }
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        GradeySectionHeader(
                            text = stringResource(R.string.today_absence_predictor),
                            modifier = Modifier
                                .weight(1f)
                                .padding(end = 8.dp),
                        )
                        TodayActionPill(
                            text = stringResource(R.string.today_plan_absence),
                            onClick = onPlanAbsence,
                            modifier = Modifier.testTag(TODAY_ABSENCE_PREDICTOR_ACTION_TEST_TAG),
                        )
                    }
                }
            }
            Spacer(Modifier.height(13.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconTile(
                    background = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.12f),
                    size = 38.dp,
                ) {
                    Icon(
                        imageVector = GradeyIcons.Calendar,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(22.dp),
                    )
                }
                Spacer(Modifier.width(13.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = stringResource(R.string.today_no_planned_absences),
                        color = MaterialTheme.colorScheme.onSurface,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = stringResource(R.string.today_plan_absence_body),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                GradeySectionHeader(
                    text = stringResource(R.string.today_new_marks_and_trends),
                    modifier = Modifier
                        .weight(1f)
                        .padding(end = 8.dp),
                )
                TodayActionPill(text = stringResource(R.string.today_view_all), onClick = onOpenTrends)
            }
            Spacer(Modifier.height(6.dp))
            newMarks.forEachIndexed { index, mark ->
                if (index > 0) {
                    HorizontalDivider(
                        modifier = Modifier.padding(start = 67.dp, end = 16.dp),
                        color = MaterialTheme.colorScheme.outlineVariant,
                    )
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(role = Role.Button, onClick = onOpenMarks)
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconTile(background = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)) {
                        Icon(
                            imageVector = GradeyIcons.CheckmarkBadge,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    Spacer(Modifier.width(13.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = stringResource(
                                R.string.today_mark_in_subject,
                                mark.markText,
                                mark.subjectName ?: stringResource(R.string.today_school_fallback),
                            ),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = MaterialTheme.colorScheme.onSurface,
                            fontSize = 16.sp,
                            lineHeight = 20.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = mark.detectedAt?.let(::formatDetectedAt)
                                ?: stringResource(R.string.today_new_from_school),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 13.sp,
                            lineHeight = 17.sp,
                        )
                    }
                }
            }
            if (newMarks.isNotEmpty() && trends.isNotEmpty()) {
                HorizontalDivider(
                    modifier = Modifier.padding(start = 67.dp, end = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant,
                )
            }
            if (trends.isEmpty()) {
                CloudHistoryEmptyRow()
            } else {
                trends.forEachIndexed { index, trend ->
                    if (index > 0) {
                        HorizontalDivider(
                            modifier = Modifier.padding(start = 67.dp, end = 16.dp),
                            color = MaterialTheme.colorScheme.outlineVariant,
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
    ) {
        GradeyAuroraBackground()
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
internal fun GradeTrendsHeader(onBack: () -> Unit) {
    val backDescription = stringResource(R.string.today_back)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .testTag(TODAY_TRENDS_BACK_TEST_TAG)
                .clip(CircleShape)
                .semantics { contentDescription = backDescription }
                .clickable(role = Role.Button, onClick = onBack),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                modifier = Modifier.size(42.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.92f),
                shadowElevation = 1.dp,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = GradeyIcons.ArrowLeft,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(28.dp),
                    )
                }
            }
        }
        Spacer(Modifier.width(8.dp))
        Text(
            text = stringResource(R.string.today_grade_movement),
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.onBackground,
            fontSize = 18.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.width(56.dp))
    }
}

@Composable
internal fun GradeTrendRangePicker(
    selected: GradeTrendRange,
    onSelected: (GradeTrendRange) -> Unit,
) {
    val useExpandableTrack = LocalDensity.current.fontScale >= 1.5f
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = if (useExpandableTrack) {
                Modifier.matchParentSize()
            } else {
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 38.dp)
            },
            shape = RoundedCornerShape(20.dp),
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.92f),
        ) {}
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .selectableGroup()
                .padding(horizontal = 2.dp),
        ) {
            GradeTrendRange.entries.forEach { range ->
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .heightIn(min = 48.dp)
                        .testTag(TODAY_RANGE_TEST_TAG_PREFIX + range.name)
                        .selectable(
                            selected = range == selected,
                            role = Role.Tab,
                            onClick = { onSelected(range) },
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 34.dp),
                        shape = RoundedCornerShape(18.dp),
                        color = if (range == selected) {
                            MaterialTheme.colorScheme.surfaceContainer
                        } else {
                            Color.Transparent
                        },
                        shadowElevation = if (range == selected) 1.dp else 0.dp,
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Text(
                                text = trendRangeLabel(range),
                                maxLines = 2,
                                color = MaterialTheme.colorScheme.onSurface,
                                fontSize = 13.sp,
                                lineHeight = 16.sp,
                                fontWeight = if (range == selected) FontWeight.Bold else FontWeight.Normal,
                                textAlign = TextAlign.Center,
                            )
                        }
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
        color = MaterialTheme.colorScheme.surfaceContainer,
        border = BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f),
        ),
        shadowElevation = 2.dp,
    ) {
        Column {
            trends.forEachIndexed { index, trend ->
                GradeTrendRow(trend)
                if (index != trends.lastIndex) {
                    HorizontalDivider(
                        modifier = Modifier.padding(start = 106.dp, end = 16.dp),
                        color = MaterialTheme.colorScheme.outlineVariant,
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
                imageVector = GradeyIcons.Sparkles,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(28.dp),
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.today_no_grade_history),
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 16.sp,
                lineHeight = 20.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text = stringResource(R.string.today_cloud_trends_subtitle),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
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
        IconTile(background = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.12f)) {
            Icon(
                imageVector = GradeyIcons.Sparkles,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(21.dp),
            )
        }
        Spacer(Modifier.width(13.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = stringResource(R.string.today_no_grade_history),
                color = MaterialTheme.colorScheme.onSurface,
                fontSize = 15.sp,
                lineHeight = 19.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = stringResource(R.string.today_cloud_trends_subtitle),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
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
            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
        ) {
            GradeTrendSparkline(trend.events.mapNotNull { it.averageValue })
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = trend.displayName,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurface,
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
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 12.sp,
                lineHeight = 15.sp,
            )
        }
        trend.averageDelta?.let { delta ->
            Text(
                text = String.format(Locale.getDefault(), "%+.2f", delta),
                color = if (delta <= 0) MaterialTheme.colorScheme.primary else DangerRed,
                fontSize = 15.sp,
                lineHeight = 18.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun GradeTrendSparkline(values: List<Double>) {
    val accent = MaterialTheme.colorScheme.primary
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
                color = accent,
                style = Stroke(width = 2.2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
            )
        }
        offsets.forEach { drawCircle(accent, radius = 2.dp.toPx(), center = it) }
    }
}

@Composable
private fun DashboardSurface(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(GradeyCardTokens.CornerRadius)
    val border = BorderStroke(
        GradeyCardTokens.OutlineWidth,
        MaterialTheme.colorScheme.onSurface.copy(alpha = GradeyCardTokens.OutlineOpacity),
    )
    if (onClick == null) {
        Surface(
            modifier = modifier.fillMaxWidth(),
            shape = shape,
            color = MaterialTheme.colorScheme.surfaceContainer,
            border = border,
            shadowElevation = GradeyCardTokens.ComposeElevation,
            content = content,
        )
    } else {
        Surface(
            modifier = modifier.fillMaxWidth(),
            onClick = onClick,
            shape = shape,
            color = MaterialTheme.colorScheme.surfaceContainer,
            border = border,
            shadowElevation = GradeyCardTokens.ComposeElevation,
            content = content,
        )
    }
}

@Composable
internal fun TodayActionPill(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(24.dp)
    Box(
        modifier = modifier
            .widthIn(min = 48.dp)
            .heightIn(min = 48.dp)
            .clip(shape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) {},
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier
                .width(IntrinsicSize.Max)
                .testTag(TODAY_ACTION_PILL_VISUAL_TEST_TAG),
            shape = shape,
            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
        ) {
            Text(
                text = text,
                modifier = Modifier
                    .heightIn(min = 28.dp)
                    .padding(horizontal = 14.dp, vertical = 6.dp),
                color = MaterialTheme.colorScheme.primary,
                fontSize = 13.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
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

private fun ScheduledLesson.displayTitle(fallback: String): String =
    subjectName?.trim()?.takeIf(String::isNotEmpty) ?: title ?: fallback

private fun ScheduledLesson.details(): String =
    listOf(timeRange.takeIf { it.isNotBlank() }, roomTitle).filterNotNull().joinToString(" · ")

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
