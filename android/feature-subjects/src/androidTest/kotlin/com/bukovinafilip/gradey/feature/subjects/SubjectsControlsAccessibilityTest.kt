package com.bukovinafilip.gradey.feature.subjects

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SubjectsControlsAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun sortOptionsExposeTabSelectionAndMinimumTargets() {
        setSortHeader(width = 360.dp)

        sortNode(SubjectSortMode.Alphabetical)
            .assert(tabRoleMatcher)
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
            .performClick()
            .assertIsSelected()

        sortNode(SubjectSortMode.Focus).assertIsNotSelected()
    }

    @Test
    fun inlineSortTargetsStayFortyEightDpAtTheNonStackBoundary() {
        setSortHeader(width = 332.dp)

        SubjectSortMode.entries.forEach { mode ->
            sortNode(mode)
                .assertHeightIsAtLeast(48.dp)
                .assertWidthIsAtLeast(48.dp)
        }
    }

    @Test
    fun sortLabelsRemainDisplayedAtTwoHundredPercentFontScale() {
        setSortHeader(fontScale = 2f)

        listOf(
            R.string.marks_sort_focus,
            R.string.marks_sort_average,
            R.string.marks_sort_name,
        ).forEach { label ->
            composeRule.onNodeWithText(context.getString(label)).assertIsDisplayed()
        }
        SubjectSortMode.entries.forEach { mode ->
            sortNode(mode)
                .assertHeightIsAtLeast(48.dp)
                .assertWidthIsAtLeast(48.dp)
        }
    }

    @Test
    fun longSortLabelWrapsInsteadOfEllipsizingOnNarrowLargeFontLayout() {
        setSortHeader(fontScale = 2f, width = 220.dp)

        composeRule.onNodeWithText(context.getString(R.string.marks_sort_average)).assertIsDisplayed()
        sortNode(SubjectSortMode.Average).assertHeightIsAtLeast(60.dp)
    }

    @Test
    fun predictionStepperUsesAButtonRoleAndFortyEightDpTarget() {
        val clicks = AtomicInteger(0)
        val label = "Increase weight"
        composeRule.setContent {
            GradeyTheme {
                StepperButton(
                    enabled = true,
                    onClick = { clicks.incrementAndGet() },
                    testTag = SUBJECT_STEPPER_INCREASE_TEST_TAG,
                    contentDescription = label,
                    tint = Color.Blue,
                ) {
                    Text("+")
                }
            }
        }

        composeRule.onNodeWithTag(
            SUBJECT_STEPPER_INCREASE_TEST_TAG,
            useUnmergedTree = true,
        )
            .assert(buttonRoleMatcher)
            .assertContentDescriptionEquals(label)
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
            .performClick()

        composeRule.runOnIdle { assertEquals(1, clicks.get()) }
    }

    @Test
    fun disabledPredictionStepperExposesDisabledStateAndSuppressesCallback() {
        val clicks = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                StepperButton(
                    enabled = false,
                    onClick = { clicks.incrementAndGet() },
                    testTag = SUBJECT_STEPPER_DECREASE_TEST_TAG,
                    contentDescription = "Decrease weight",
                    tint = Color.Blue,
                ) {
                    Text("-")
                }
            }
        }

        composeRule.onNodeWithTag(
            SUBJECT_STEPPER_DECREASE_TEST_TAG,
            useUnmergedTree = true,
        )
            .assert(buttonRoleMatcher)
            .assertContentDescriptionEquals("Decrease weight")
            .assertIsNotEnabled()
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
            .performClick()

        composeRule.runOnIdle { assertEquals(0, clicks.get()) }
    }

    @Test
    fun fullPredictionStepperKeepsBothTargetsAtLargeFontAndCompactWidth() {
        val decreaseClicks = AtomicInteger(0)
        val increaseClicks = AtomicInteger(0)
        composeRule.setContent {
            val baseDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(baseDensity.density, 2f),
            ) {
                GradeyTheme {
                    Box(modifier = Modifier.width(220.dp)) {
                        PredictionWeightStepperRow(
                            enabled = true,
                            weight = 5,
                            onDecreaseWeight = { decreaseClicks.incrementAndGet() },
                            onIncreaseWeight = { increaseClicks.incrementAndGet() },
                        )
                    }
                }
            }
        }

        val decrease = composeRule.onNodeWithTag(
            SUBJECT_STEPPER_DECREASE_TEST_TAG,
            useUnmergedTree = true,
        ).assertMinimumTarget()
        val increase = composeRule.onNodeWithTag(
            SUBJECT_STEPPER_INCREASE_TEST_TAG,
            useUnmergedTree = true,
        ).assertMinimumTarget()
        val weightLabel = composeRule
            .onNodeWithText(context.getString(R.string.subject_prediction_weight, 5))
            .assertIsDisplayed()

        val decreaseBounds = decrease.fetchSemanticsNode().boundsInRoot
        val increaseBounds = increase.fetchSemanticsNode().boundsInRoot
        val labelBounds = weightLabel.fetchSemanticsNode().boundsInRoot
        assertTrue("Decrease action and weight label must not overlap", decreaseBounds.right <= labelBounds.left)
        assertTrue("Weight label and increase action must not overlap", labelBounds.right <= increaseBounds.left)

        decrease.performClick()
        increase.performClick()
        composeRule.runOnIdle {
            assertEquals(1, decreaseClicks.get())
            assertEquals(1, increaseClicks.get())
        }
    }

    @Test
    fun retainedRefreshRetryUsesButtonRoleAndMinimumTarget() {
        val clicks = AtomicInteger(0)
        setRefreshError(isRefreshing = false) { clicks.incrementAndGet() }

        refreshRetryNode()
            .assert(buttonRoleMatcher)
            .assertHasClickAction()
            .assertIsEnabled()
            .assertMinimumTarget()
            .performClick()

        composeRule.runOnIdle { assertEquals(1, clicks.get()) }
    }

    @Test
    fun retainedRefreshRetryDisablesAndSuppressesCallbackWhileRefreshing() {
        val clicks = AtomicInteger(0)
        setRefreshError(isRefreshing = true) { clicks.incrementAndGet() }

        refreshRetryNode()
            .assert(buttonRoleMatcher)
            .assertHasClickAction()
            .assertIsNotEnabled()
            .assertMinimumTarget()
            .performClick()

        composeRule.runOnIdle { assertEquals(0, clicks.get()) }
    }

    private fun setSortHeader(
        fontScale: Float = 1f,
        width: androidx.compose.ui.unit.Dp = 320.dp,
    ) {
        composeRule.setContent {
            val baseDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(baseDensity.density, fontScale),
            ) {
                var selected by remember { mutableStateOf(SubjectSortMode.Focus) }
                GradeyTheme {
                    Box(
                        modifier = Modifier
                            .width(width)
                            .padding(horizontal = 16.dp),
                    ) {
                        SubjectsSectionHeader(
                            sortMode = selected,
                            onSortModeChange = { selected = it },
                        )
                    }
                }
            }
        }
    }

    private fun setRefreshError(
        isRefreshing: Boolean,
        onRefresh: () -> Unit,
    ) {
        composeRule.setContent {
            GradeyTheme {
                SubjectsScreen(
                    subjects = emptyList(),
                    absence = AbsenceResponse(),
                    onPredictSubjectAverage = { _, _, _ -> null },
                    refreshErrorMessage = "offline",
                    isRefreshing = isRefreshing,
                    onRefresh = onRefresh,
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                )
            }
        }
    }

    private fun refreshRetryNode() = composeRule
        .onNodeWithText(context.getString(R.string.marks_refresh_retry))
        .performScrollTo()

    private fun sortNode(mode: SubjectSortMode) = composeRule.onNodeWithTag(
        SUBJECT_SORT_TEST_TAG_PREFIX + mode.name,
        useUnmergedTree = true,
    )

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertMinimumTarget() =
        assertHeightIsAtLeast(48.dp).assertWidthIsAtLeast(48.dp)

    private companion object {
        val tabRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}
