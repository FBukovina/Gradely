package com.bukovinafilip.gradey.feature.absence

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.domain.AbsenceLessonCandidate
import com.bukovinafilip.gradey.domain.DemoData
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AbsencePredictionRestorationTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun selectedDayDraftAndCompletedPlanSurviveStateRestoration() {
        val restorationTester = StateRestorationTester(composeRule)
        val loadedDateKeys = CopyOnWriteArrayList<String>()
        restorationTester.setContent {
            GradeyTheme {
                AbsenceScreen(
                    response = DemoData.absenceResponse,
                    studentName = "Test Student",
                    isRefreshing = false,
                    isResolvingSubjects = false,
                    subjectResolutionProgress = null,
                    subjectResolutionWarning = null,
                    subjectResolutionError = null,
                    unresolvedPartialDays = emptyList(),
                    onRefresh = {},
                    onRetrySubjectResolution = {},
                    onSaveManualSelections = { null },
                    predictorScopeKey = "prediction-restoration-test",
                    onLoadPredictionLessons = { dateKey ->
                        loadedDateKeys += dateKey
                        listOf(predictionLesson(dateKey))
                    },
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                )
            }
        }

        composeRule.onNodeWithText(planAbsenceLabel)
            .performScrollTo()
            .performClick()
        composeRule.waitUntil { loadedDateKeys.isNotEmpty() }
        val firstDateKey = loadedDateKeys.last()
        composeRule.onNodeWithText(lessonLabel(firstDateKey)).assertIsDisplayed().performClick()
        composeRule.onNodeWithText(selectedCountLabel(1)).assertIsDisplayed()

        composeRule.onNodeWithText(nextDayLabel).performClick()
        composeRule.waitUntil {
            loadedDateKeys.lastOrNull()?.let { it != firstDateKey } == true
        }
        val selectedDateKey = loadedDateKeys.last()
        val selectedLessonLabel = lessonLabel(selectedDateKey)
        composeRule.onNodeWithText(selectedLessonLabel).assertIsDisplayed().performClick()
        composeRule.onNodeWithText(selectedCountLabel(2)).assertIsDisplayed()

        val callsBeforeDraftRestore = loadedDateKeys.size
        restorationTester.emulateSavedInstanceStateRestore()

        composeRule.onNodeWithText(selectedCountLabel(2)).assertIsDisplayed()
        composeRule.waitUntil { loadedDateKeys.size > callsBeforeDraftRestore }
        assertEquals(selectedDateKey, loadedDateKeys.last())
        composeRule.onNodeWithText(selectedLessonLabel).assertIsDisplayed()
        composeRule.onNodeWithText(doneLabel).performClick()

        composeRule.onNodeWithText(editPlanLabel).assertIsDisplayed()
        restorationTester.emulateSavedInstanceStateRestore()

        composeRule.onNodeWithText(editPlanLabel).assertIsDisplayed().performClick()
        composeRule.onNodeWithText(selectedCountLabel(2)).assertIsDisplayed()
    }

    @Test
    fun completedPlanIsDiscardedWhenStateRestoresIntoAnotherSchoolScope() {
        val restorationTester = StateRestorationTester(composeRule)
        val loadedDateKeys = CopyOnWriteArrayList<String>()
        var schoolScope = "school-a"
        restorationTester.setContent {
            GradeyTheme {
                AbsenceScreen(
                    response = DemoData.absenceResponse,
                    studentName = "Test Student",
                    isRefreshing = false,
                    isResolvingSubjects = false,
                    subjectResolutionProgress = null,
                    subjectResolutionWarning = null,
                    subjectResolutionError = null,
                    unresolvedPartialDays = emptyList(),
                    onRefresh = {},
                    onRetrySubjectResolution = {},
                    onSaveManualSelections = { null },
                    predictorScopeKey = schoolScope,
                    onLoadPredictionLessons = { dateKey ->
                        loadedDateKeys += dateKey
                        listOf(predictionLesson(dateKey))
                    },
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                )
            }
        }

        composeRule.onNodeWithText(planAbsenceLabel).performScrollTo().performClick()
        composeRule.waitUntil { loadedDateKeys.isNotEmpty() }
        composeRule.onNodeWithText(lessonLabel(loadedDateKeys.last()))
            .assertIsDisplayed()
            .performClick()
        composeRule.onNodeWithText(doneLabel).performClick()
        composeRule.onNodeWithText(editPlanLabel).assertIsDisplayed()

        // Keep the old composition alive until StateRestorationTester captures it, then make the
        // recreated composition read the new owner without first giving an effect a chance to clear.
        schoolScope = "school-b"
        restorationTester.emulateSavedInstanceStateRestore()

        composeRule.onNodeWithText(editPlanLabel).assertDoesNotExist()
        composeRule.onNodeWithText(planAbsenceLabel).assertIsDisplayed()
    }

    private fun predictionLesson(dateKey: String) = AbsenceLessonCandidate(
        id = "prediction-$dateKey-biology",
        dateKey = dateKey,
        hourID = "1",
        hourCaption = "1",
        timeRange = "08:00-08:45",
        subjectKey = "biology",
        subjectName = "Biology $dateKey",
    )

    private fun lessonLabel(dateKey: String) = "1. Biology $dateKey"

    private fun selectedCountLabel(count: Int): String =
        context.getString(R.string.absence_predictor_selected_count, count)

    private val planAbsenceLabel: String
        get() = context.getString(R.string.absence_predictor_open)

    private val editPlanLabel: String
        get() = context.getString(R.string.absence_predictor_edit)

    private val nextDayLabel: String
        get() = context.getString(R.string.absence_predictor_next_day)

    private val doneLabel: String
        get() = context.getString(R.string.absence_predictor_done)
}
