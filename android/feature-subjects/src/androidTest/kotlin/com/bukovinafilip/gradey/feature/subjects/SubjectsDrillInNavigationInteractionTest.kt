package com.bukovinafilip.gradey.feature.subjects

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.dp
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.SubjectInfo
import com.bukovinafilip.gradey.ui.GradeyTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SubjectsDrillInNavigationInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun subjectRowOpensDetailAndVisibleBackReturnsToOverview() {
        setScreen()

        subjectRow()
            .performScrollTo()
            .assert(buttonRoleMatcher)
            .assertHasClickAction()
            .assertMinimumTarget()
            .performClick()

        detailBack()
            .assertIsDisplayed()
            .assert(buttonRoleMatcher)
            .assertHasClickAction()
            .assertContentDescriptionEquals(context.getString(R.string.subject_back))
            .assertMinimumTarget()
            .performClick()

        detailBack().assertDoesNotExist()
        subjectRow().performScrollTo().assertIsDisplayed()
    }

    @Test
    fun systemBackFromDetailReturnsToOverview() {
        setScreen()

        subjectRow().performScrollTo().performClick()
        detailBack().assertIsDisplayed()

        Espresso.pressBack()
        composeRule.waitForIdle()

        detailBack().assertDoesNotExist()
        subjectRow().performScrollTo().assertIsDisplayed()
    }

    private fun setScreen() {
        composeRule.setContent {
            GradeyTheme {
                SubjectsScreen(
                    subjects = listOf(TestSubject),
                    absence = AbsenceResponse(),
                    onPredictSubjectAverage = { _, _, _ -> null },
                    isRefreshing = false,
                    onRefresh = {},
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                )
            }
        }
    }

    private fun subjectRow() = composeRule.onNodeWithTag(
        SUBJECT_ROW_TEST_TAG_PREFIX + TestSubject.id,
        useUnmergedTree = true,
    )

    private fun detailBack() = composeRule.onNodeWithTag(
        SUBJECT_DETAIL_BACK_TEST_TAG,
        useUnmergedTree = true,
    )

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertMinimumTarget() =
        assertHeightIsAtLeast(48.dp).assertWidthIsAtLeast(48.dp)

    private companion object {
        val TestSubject = Subject(
            subjectInfo = SubjectInfo(
                id = "math",
                abbrev = "M",
                name = "Mathematics",
            ),
        )
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}
