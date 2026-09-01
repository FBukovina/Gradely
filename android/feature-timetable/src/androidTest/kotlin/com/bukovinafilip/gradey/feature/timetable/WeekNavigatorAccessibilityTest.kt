package com.bukovinafilip.gradey.feature.timetable

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.time.LocalDate
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WeekNavigatorAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun navigationActionsExposeButtonRolesMinimumTargetsAndCallbacks() {
        val previousClicks = AtomicInteger(0)
        val nextClicks = AtomicInteger(0)
        val todayClicks = AtomicInteger(0)
        setNavigator(
            onPrevious = { previousClicks.incrementAndGet() },
            onNext = { nextClicks.incrementAndGet() },
            onToday = { todayClicks.incrementAndGet() },
        )

        actionNode(TIMETABLE_PREVIOUS_WEEK_TEST_TAG)
            .assert(buttonRoleMatcher)
            .assertContentDescriptionEquals(context.getString(R.string.timetable_previous_week))
            .assertMinimumTarget()
            .performClick()
        actionNode(TIMETABLE_NEXT_WEEK_TEST_TAG)
            .assert(buttonRoleMatcher)
            .assertContentDescriptionEquals(context.getString(R.string.timetable_next_week))
            .assertMinimumTarget()
            .performClick()
        actionNode(TIMETABLE_TODAY_TEST_TAG)
            .assert(buttonRoleMatcher)
            .assertContentDescriptionEquals(context.getString(R.string.timetable_today))
            .assertMinimumTarget()
            .performClick()

        composeRule.runOnIdle {
            assertEquals(1, previousClicks.get())
            assertEquals(1, nextClicks.get())
            assertEquals(1, todayClicks.get())
        }
    }

    @Test
    fun weekAndTodayLabelsRemainDisplayedAtTwoHundredPercentFontScale() {
        val monday = LocalDate.of(2024, 1, 29)
        setNavigator(fontScale = 2f, monday = monday)

        actionNode(TIMETABLE_TODAY_TEST_TAG).assertIsDisplayed()
        actionNode(TIMETABLE_PREVIOUS_WEEK_TEST_TAG).assertIsDisplayed()
        actionNode(TIMETABLE_NEXT_WEEK_TEST_TAG).assertIsDisplayed()
        val weekBounds = composeRule
            .onNodeWithText(formatWeekRange(monday, Locale.US))
            .assertIsDisplayed()
            .fetchSemanticsNode().boundsInRoot
        val previousBounds = actionNode(TIMETABLE_PREVIOUS_WEEK_TEST_TAG)
            .fetchSemanticsNode().boundsInRoot
        val nextBounds = actionNode(TIMETABLE_NEXT_WEEK_TEST_TAG)
            .fetchSemanticsNode().boundsInRoot
        assertTrue("Previous action and week label must not overlap", previousBounds.right <= weekBounds.left)
        assertTrue("Week label and next action must not overlap", weekBounds.right <= nextBounds.left)
    }

    @Test
    fun disabledNavigationActionsExposeDisabledStateAndSuppressCallbacks() {
        val previousClicks = AtomicInteger(0)
        val nextClicks = AtomicInteger(0)
        val todayClicks = AtomicInteger(0)
        setNavigator(
            enabled = false,
            onPrevious = { previousClicks.incrementAndGet() },
            onNext = { nextClicks.incrementAndGet() },
            onToday = { todayClicks.incrementAndGet() },
        )

        listOf(
            TIMETABLE_PREVIOUS_WEEK_TEST_TAG,
            TIMETABLE_NEXT_WEEK_TEST_TAG,
            TIMETABLE_TODAY_TEST_TAG,
        ).forEach { tag ->
            actionNode(tag).assertIsNotEnabled().performClick()
        }

        composeRule.runOnIdle {
            assertEquals(0, previousClicks.get())
            assertEquals(0, nextClicks.get())
            assertEquals(0, todayClicks.get())
        }
    }

    private fun setNavigator(
        fontScale: Float = 1f,
        monday: LocalDate = LocalDate.of(2000, 1, 3),
        enabled: Boolean = true,
        onPrevious: () -> Unit = {},
        onNext: () -> Unit = {},
        onToday: () -> Unit = {},
    ) {
        composeRule.setContent {
            val baseDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(baseDensity.density, fontScale),
            ) {
                GradeyTheme {
                    Box(modifier = Modifier.width(320.dp)) {
                        WeekNavigator(
                            monday = monday,
                            locale = Locale.US,
                            enabled = enabled,
                            onPrevious = onPrevious,
                            onNext = onNext,
                            onToday = onToday,
                        )
                    }
                }
            }
        }
    }

    private fun actionNode(tag: String) = composeRule.onNodeWithTag(tag, useUnmergedTree = true)

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertMinimumTarget() =
        assertHeightIsAtLeast(48.dp).assertWidthIsAtLeast(48.dp)

    private companion object {
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}
