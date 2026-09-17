package com.bukovinafilip.gradey.feature.absence

import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bukovinafilip.gradey.domain.DemoData
import com.bukovinafilip.gradey.ui.GradeyTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AbsenceInitialModeRestorationTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun firstCompositionDefaultsToDaysAndLaterSelectionSurvivesRestoration() {
        val restorationTester = StateRestorationTester(composeRule)
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
                    predictorScopeKey = "absence-mode-restoration-test",
                    onLoadPredictionLessons = { emptyList() },
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                )
            }
        }

        modeNode(AbsenceMode.Days).performScrollTo().assertIsSelected()
        modeNode(AbsenceMode.Subjects).assertIsNotSelected()

        modeNode(AbsenceMode.Months).performClick().assertIsSelected()
        modeNode(AbsenceMode.Days).assertIsNotSelected()

        restorationTester.emulateSavedInstanceStateRestore()

        modeNode(AbsenceMode.Months).performScrollTo().assertIsSelected()
        modeNode(AbsenceMode.Days).assertIsNotSelected()
    }

    private fun modeNode(mode: AbsenceMode) = composeRule.onNodeWithTag(
        ABSENCE_MODE_TEST_TAG_PREFIX + mode.name,
        useUnmergedTree = true,
    )
}
