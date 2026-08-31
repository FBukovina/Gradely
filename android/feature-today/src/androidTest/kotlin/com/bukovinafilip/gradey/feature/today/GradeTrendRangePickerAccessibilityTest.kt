package com.bukovinafilip.gradey.feature.today

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.domain.GradeTrendRange
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GradeTrendRangePickerAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun rangeOptionsExposeTabSelectionAndMinimumTargets() {
        setPicker()

        val thirtyDays = rangeNode(GradeTrendRange.THIRTY_DAYS)
        thirtyDays
            .assert(tabRoleMatcher)
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
            .performClick()
            .assertIsSelected()

        rangeNode(GradeTrendRange.NINETY_DAYS).assertIsNotSelected()
    }

    @Test
    fun rangeLabelsRemainDisplayedAtTwoHundredPercentFontScale() {
        setPicker(fontScale = 2f)

        listOf(
            R.string.today_range_30,
            R.string.today_range_90,
            R.string.today_school_year,
        ).forEach { label ->
            composeRule.onNodeWithText(context.getString(label)).assertIsDisplayed()
        }
        rangeNode(GradeTrendRange.SCHOOL_YEAR).assertHeightIsAtLeast(60.dp)
    }

    @Test
    fun trendsBackActionUsesAStableLabelAndMinimumTarget() {
        val clicks = AtomicInteger(0)
        setHeader(onBack = { clicks.incrementAndGet() })

        composeRule.onNodeWithTag(TODAY_TRENDS_BACK_TEST_TAG, useUnmergedTree = true)
            .assert(buttonRoleMatcher)
            .assertContentDescriptionEquals(context.getString(R.string.today_back))
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
            .performClick()

        composeRule.runOnIdle { assertEquals(1, clicks.get()) }
    }

    @Test
    fun trendsTitleDoesNotOverlapBackAtTwoHundredPercentOnCompactWidth() {
        setHeader(fontScale = 2f)

        val backBounds = composeRule
            .onNodeWithTag(TODAY_TRENDS_BACK_TEST_TAG, useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot
        val titleBounds = composeRule
            .onNodeWithText(context.getString(R.string.today_grade_movement))
            .assertIsDisplayed()
            .fetchSemanticsNode().boundsInRoot

        assertTrue("Back and title must not overlap", backBounds.right <= titleBounds.left)
    }

    private fun setPicker(fontScale: Float = 1f) {
        composeRule.setContent {
            val baseDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(baseDensity.density, fontScale),
            ) {
                var selected by remember { mutableStateOf(GradeTrendRange.NINETY_DAYS) }
                GradeyTheme {
                    Box(modifier = Modifier.width(288.dp)) {
                        GradeTrendRangePicker(
                            selected = selected,
                            onSelected = { selected = it },
                        )
                    }
                }
            }
        }
    }

    private fun setHeader(
        fontScale: Float = 1f,
        onBack: () -> Unit = {},
    ) {
        composeRule.setContent {
            val baseDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(baseDensity.density, fontScale),
            ) {
                GradeyTheme {
                    Box(modifier = Modifier.width(288.dp)) {
                        GradeTrendsHeader(onBack = onBack)
                    }
                }
            }
        }
    }

    private fun rangeNode(range: GradeTrendRange) = composeRule.onNodeWithTag(
        TODAY_RANGE_TEST_TAG_PREFIX + range.name,
        useUnmergedTree = true,
    )

    private companion object {
        val tabRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}
