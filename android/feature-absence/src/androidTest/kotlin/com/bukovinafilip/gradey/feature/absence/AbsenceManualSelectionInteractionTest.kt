package com.bukovinafilip.gradey.feature.absence

import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.dp
import androidx.test.espresso.Espresso.pressBack
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.domain.AbsenceLessonCandidate
import com.bukovinafilip.gradey.domain.AbsencePartialDayCandidate
import com.bukovinafilip.gradey.domain.DemoData
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AbsenceManualSelectionInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun manualLessonRowExposesOneFullRowCheckboxStateAndDecorativeGlyph() {
        setScreen { null }

        openManualSheet()
        lessonNode(FirstLessonID)
            .assert(checkboxRoleMatcher)
            .assert(toggleStateMatcher(ToggleableState.Off))
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
            .performClick()
            .assert(toggleStateMatcher(ToggleableState.On))

        composeRule.onAllNodes(
            hasClickAction() and hasAnyAncestor(
                hasTestTag(ABSENCE_MANUAL_LESSON_TEST_TAG_PREFIX + FirstLessonID),
            ),
            useUnmergedTree = true,
        ).assertCountEquals(0)
        composeRule.onNodeWithText("○", useUnmergedTree = true).assertDoesNotExist()
        composeRule.onNodeWithText("✓", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test
    fun manualLessonRowDisablesAndSuppressesToggleWhileSaving() {
        val saveStarted = CompletableDeferred<Unit>()
        val releaseSave = CompletableDeferred<Unit>()
        setScreen {
            saveStarted.complete(Unit)
            releaseSave.await()
            null
        }

        openManualSheet()
        lessonNode(FirstLessonID).performClick()
        composeRule.onNodeWithText(saveLabel).performClick()
        composeRule.waitUntil { saveStarted.isCompleted }

        lessonNode(FirstLessonID)
            .assert(checkboxRoleMatcher)
            .assert(toggleStateMatcher(ToggleableState.On))
            .assertIsNotEnabled()
            .assertHasClickAction()
            .performClick()
            .assert(toggleStateMatcher(ToggleableState.On))
        composeRule.onNodeWithText(selectedCount(1)).assertIsDisplayed()

        releaseSave.complete(Unit)
        waitForSheetToDismiss()
    }

    @Test
    fun exactQuotaSavesExactLessonIDsAndDismissesSheet() {
        val saveCount = AtomicInteger(0)
        val savedSelections = AtomicReference<Map<String, Set<String>>>()
        setScreen { selections ->
            saveCount.incrementAndGet()
            savedSelections.set(selections.mapValues { (_, lessonIDs) -> lessonIDs.toSet() })
            null
        }

        openManualSheet()
        composeRule.onNodeWithText(saveLabel).assertIsNotEnabled()

        composeRule.onNodeWithText(firstLessonLabel).performClick()
        composeRule.onNodeWithText(selectedCount(1)).assertIsDisplayed()
        composeRule.onNodeWithText(saveLabel).assertIsEnabled()

        composeRule.onNodeWithText(secondLessonLabel).performClick()
        composeRule.onNodeWithText(selectedCount(1)).assertIsDisplayed()
        composeRule.onNodeWithText(saveLabel).performClick()

        composeRule.waitUntil { saveCount.get() == 1 }
        assertEquals(mapOf(DateKey to setOf(FirstLessonID)), savedSelections.get())
        waitForSheetToDismiss()
    }

    @Test
    fun saveFailureRetainsDraftAndSuccessfulRetryDismissesSheet() {
        val saveCount = AtomicInteger(0)
        val lastSelections = AtomicReference<Map<String, Set<String>>>()
        setScreen { selections ->
            lastSelections.set(selections.mapValues { (_, lessonIDs) -> lessonIDs.toSet() })
            if (saveCount.incrementAndGet() == 1) SaveFailure else null
        }

        openManualSheet()
        composeRule.onNodeWithText(firstLessonLabel).performClick()
        composeRule.onNodeWithText(saveLabel).performClick()

        composeRule.waitUntil { saveCount.get() == 1 }
        composeRule.onNodeWithText(SaveFailure).assertIsDisplayed()
        composeRule.onNodeWithText(selectedCount(1)).assertIsDisplayed()
        composeRule.onNodeWithText(saveLabel).assertIsEnabled().performClick()

        composeRule.waitUntil { saveCount.get() == 2 }
        assertEquals(mapOf(DateKey to setOf(FirstLessonID)), lastSelections.get())
        waitForSheetToDismiss()
    }

    @Test
    fun openSheetAndSelectedDraftSurviveStateRestoration() {
        val restorationTester = StateRestorationTester(composeRule)
        val savedSelections = AtomicReference<Map<String, Set<String>>>()
        restorationTester.setContent {
            TestScreen { selections ->
                savedSelections.set(selections.mapValues { (_, lessonIDs) -> lessonIDs.toSet() })
                null
            }
        }

        openManualSheet()
        composeRule.onNodeWithText(firstLessonLabel).performClick()
        composeRule.onNodeWithText(selectedCount(1)).assertIsDisplayed()

        restorationTester.emulateSavedInstanceStateRestore()

        composeRule.onNodeWithText(sheetTitle).assertIsDisplayed()
        composeRule.onNodeWithText(selectedCount(1)).assertIsDisplayed()
        composeRule.onNodeWithText(saveLabel).assertIsEnabled().performClick()
        composeRule.waitUntil { savedSelections.get() != null }
        assertEquals(mapOf(DateKey to setOf(FirstLessonID)), savedSelections.get())
    }

    @Test
    fun restoredDraftDropsLessonIDsMissingFromCurrentCandidates() {
        val restorationTester = StateRestorationTester(composeRule)
        val currentDays = AtomicReference(listOf(PartialDay))
        val savedSelections = AtomicReference<Map<String, Set<String>>>()
        restorationTester.setContent {
            TestScreen(
                unresolvedPartialDays = currentDays.get(),
                onSave = { selections ->
                    savedSelections.set(selections.mapValues { (_, lessonIDs) -> lessonIDs.toSet() })
                    null
                },
            )
        }

        openManualSheet()
        composeRule.onNodeWithText(firstLessonLabel).performClick()
        composeRule.onNodeWithText(selectedCount(1)).assertIsDisplayed()

        currentDays.set(listOf(ChangedPartialDay))
        restorationTester.emulateSavedInstanceStateRestore()

        composeRule.onNodeWithText(sheetTitle).assertIsDisplayed()
        composeRule.onNodeWithText(selectedCount(0)).assertIsDisplayed()
        composeRule.onNodeWithText(saveLabel).assertIsNotEnabled()
        composeRule.onNodeWithText(secondLessonLabel).performClick()
        composeRule.onNodeWithText(saveLabel).assertIsEnabled().performClick()
        composeRule.waitUntil { savedSelections.get() != null }
        assertEquals(mapOf(DateKey to setOf(SecondLessonID)), savedSelections.get())
    }

    @Test
    fun restoredSheetAndDraftDoNotCrossSchoolScope() {
        val restorationTester = StateRestorationTester(composeRule)
        val currentScope = AtomicReference("school-a")
        restorationTester.setContent {
            TestScreen(
                predictorScopeKey = currentScope.get(),
                onSave = { null },
            )
        }

        openManualSheet()
        composeRule.onNodeWithText(firstLessonLabel).performClick()
        composeRule.onNodeWithText(selectedCount(1)).assertIsDisplayed()

        currentScope.set("school-b")
        restorationTester.emulateSavedInstanceStateRestore()

        waitForSheetToDismiss()
        composeRule.onNodeWithText(chooseLessonsLabel).assertIsDisplayed()
    }

    @Test
    fun systemBackDismissesSheetWithoutSaving() {
        val saveCount = AtomicInteger(0)
        val savedSelections = AtomicReference<Map<String, Set<String>>>()
        setScreen { selections ->
            saveCount.incrementAndGet()
            savedSelections.set(selections)
            null
        }

        openManualSheet()
        composeRule.onNodeWithText(firstLessonLabel).performClick()
        pressBack()

        waitForSheetToDismiss()
        assertEquals(0, saveCount.get())
        assertNull(savedSelections.get())
        composeRule.onNodeWithText(chooseLessonsLabel).assertIsDisplayed()
    }

    private fun setScreen(onSave: suspend (Map<String, Set<String>>) -> String?) {
        composeRule.setContent { TestScreen(onSave = onSave) }
    }

    @Composable
    private fun TestScreen(
        unresolvedPartialDays: List<AbsencePartialDayCandidate> = listOf(PartialDay),
        predictorScopeKey: String = "absence-interaction-test",
        onSave: suspend (Map<String, Set<String>>) -> String?,
    ) {
        GradeyTheme {
            AbsenceScreen(
                response = DemoData.absenceResponse,
                studentName = "Test Student",
                isRefreshing = false,
                isResolvingSubjects = false,
                subjectResolutionProgress = null,
                subjectResolutionWarning = null,
                subjectResolutionError = null,
                unresolvedPartialDays = unresolvedPartialDays,
                onRefresh = {},
                onRetrySubjectResolution = {},
                onSaveManualSelections = onSave,
                predictorScopeKey = predictorScopeKey,
                onLoadPredictionLessons = { emptyList() },
                onOpenAccount = {},
                onOpenGradeyTools = {},
            )
        }
    }

    private fun openManualSheet() {
        composeRule.onNodeWithText(chooseLessonsLabel)
            .performScrollTo()
            .performClick()
        composeRule.onNodeWithText(sheetTitle).assertIsDisplayed()
    }

    private fun waitForSheetToDismiss() {
        composeRule.waitUntil(timeoutMillis = 5_000) {
            runCatching {
                composeRule.onNodeWithText(sheetTitle).assertDoesNotExist()
            }.isSuccess
        }
    }

    private fun selectedCount(count: Int): String = context.getString(
        R.string.absence_manual_selected_count,
        count,
        PartialDay.requiredSelectionCount,
    )

    private val chooseLessonsLabel: String
        get() = context.getString(R.string.absence_manual_callout_button)

    private val sheetTitle: String
        get() = context.getString(R.string.absence_manual_title)

    private val saveLabel: String
        get() = context.getString(R.string.absence_manual_save)

    private fun lessonNode(lessonID: String) = composeRule.onNodeWithTag(
        ABSENCE_MANUAL_LESSON_TEST_TAG_PREFIX + lessonID,
        useUnmergedTree = true,
    )

    private companion object {
        const val DateKey = "2026-09-01"
        const val FirstLessonID = "lesson-$DateKey-1-biology"
        const val SecondLessonID = "lesson-$DateKey-2-mathematics"
        const val SaveFailure = "Saving the selections failed"
        const val firstLessonLabel = "1. Biology"
        const val secondLessonLabel = "2. Mathematics"

        val checkboxRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox)

        fun toggleStateMatcher(state: ToggleableState) = SemanticsMatcher.expectValue(
            SemanticsProperties.ToggleableState,
            state,
        )

        val PartialDay = AbsencePartialDayCandidate(
            dateKey = DateKey,
            requiredSelectionCount = 1,
            selectedLessonIDs = emptyList(),
            lessons = listOf(
                AbsenceLessonCandidate(
                    id = FirstLessonID,
                    dateKey = DateKey,
                    hourID = "1",
                    hourCaption = "1",
                    timeRange = "08:00-08:45",
                    subjectKey = "biology",
                    subjectName = "Biology",
                ),
                AbsenceLessonCandidate(
                    id = SecondLessonID,
                    dateKey = DateKey,
                    hourID = "2",
                    hourCaption = "2",
                    timeRange = "08:55-09:40",
                    subjectKey = "mathematics",
                    subjectName = "Mathematics",
                ),
            ),
        )
        val ChangedPartialDay = PartialDay.copy(lessons = listOf(PartialDay.lessons.last()))
    }
}
