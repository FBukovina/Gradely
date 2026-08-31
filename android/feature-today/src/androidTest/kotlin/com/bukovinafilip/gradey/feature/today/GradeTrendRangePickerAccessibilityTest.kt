package com.bukovinafilip.gradey.feature.today

import android.content.res.Configuration
import android.os.LocaleList
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertHasClickAction
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
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    @Test
    fun todayActionPillKeepsButtonSemanticsAndTargetAtTwoHundredPercentFontScale() {
        val clicks = AtomicInteger(0)
        val label = "Plan absence"
        composeRule.setContent {
            val baseDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(baseDensity.density, 2f),
            ) {
                GradeyTheme {
                    TodayActionPill(
                        text = label,
                        onClick = { clicks.incrementAndGet() },
                        modifier = Modifier.testTag(TODAY_ACTION_PILL_TEST_TAG),
                    )
                }
            }
        }

        composeRule.onNodeWithTag(TODAY_ACTION_PILL_TEST_TAG, useUnmergedTree = true)
            .assert(buttonRoleMatcher)
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
            .performClick()
        composeRule.onNodeWithText(label, useUnmergedTree = true).assertIsDisplayed()
        composeRule.onNodeWithTag(TODAY_ACTION_PILL_VISUAL_TEST_TAG, useUnmergedTree = true)
            .assertHeightIsAtLeast(40.dp)
        composeRule.runOnIdle { assertEquals(1, clicks.get()) }
    }

    @Test
    fun absencePredictorCardContainsCompactCzechContentAtTwoHundredPercentFontScale() {
        val clicks = AtomicInteger(0)
        setAbsencePredictorCard(
            localeTag = "cs",
            fontScale = 2f,
            width = 320.dp,
            onPlanAbsence = { clicks.incrementAndGet() },
        )

        val cardBounds = composeRule
            .onNodeWithTag(TODAY_ABSENCE_PREDICTOR_CARD_TEST_TAG, useUnmergedTree = true)
            .assertIsDisplayed()
            .assertHeightIsAtLeast(139.dp)
            .fetchSemanticsNode()
            .boundsInRoot
        val titleNode = composeRule.onNodeWithText(
            localizedString(R.string.today_absence_predictor, "cs"),
            useUnmergedTree = true,
        ).assertIsDisplayed().assertNoVisualOverflow("Predictor title")
        val actionLabelNode = composeRule.onNodeWithText(
            localizedString(R.string.today_plan_absence, "cs"),
            useUnmergedTree = true,
        ).assertIsDisplayed().assertNoVisualOverflow("Plan-absence label")
        val emptyStateNode = composeRule.onNodeWithText(
            localizedString(R.string.today_no_planned_absences, "cs"),
            useUnmergedTree = true,
        ).assertIsDisplayed().assertNoVisualOverflow("Empty-state title")
        val bodyNode = composeRule.onNodeWithText(
            localizedString(R.string.today_plan_absence_body, "cs"),
            useUnmergedTree = true,
        ).assertIsDisplayed().assertNoVisualOverflow("Predictor body")
        val actionNode = composeRule
            .onNodeWithTag(TODAY_ABSENCE_PREDICTOR_ACTION_TEST_TAG, useUnmergedTree = true)
            .assert(buttonRoleMatcher)
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)

        val titleBounds = titleNode.fetchSemanticsNode().boundsInRoot
        val actionBounds = actionNode.fetchSemanticsNode().boundsInRoot
        val actionLabelBounds = actionLabelNode.fetchSemanticsNode().boundsInRoot
        val emptyStateBounds = emptyStateNode.fetchSemanticsNode().boundsInRoot
        val bodyBounds = bodyNode.fetchSemanticsNode().boundsInRoot
        listOf(
            "Predictor title" to titleBounds,
            "Plan-absence target" to actionBounds,
            "Plan-absence label" to actionLabelBounds,
            "Empty-state title" to emptyStateBounds,
            "Predictor body" to bodyBounds,
        ).forEach { (label, bounds) ->
            assertTrue(
                "$label must remain fully inside the predictor card",
                bounds.left >= cardBounds.left &&
                    bounds.right <= cardBounds.right &&
                    bounds.top >= cardBounds.top &&
                    bounds.bottom <= cardBounds.bottom,
            )
        }
        assertTrue("Stacked title and action must not overlap", titleBounds.bottom <= actionBounds.top)
        assertTrue("Action and predictor body must not overlap", actionBounds.bottom <= emptyStateBounds.top)

        actionNode.performClick()
        composeRule.runOnIdle { assertEquals(1, clicks.get()) }
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

    private fun setAbsencePredictorCard(
        localeTag: String,
        fontScale: Float,
        width: androidx.compose.ui.unit.Dp,
        onPlanAbsence: () -> Unit,
    ) {
        composeRule.setContent {
            val baseContext = LocalContext.current
            val baseConfiguration = LocalConfiguration.current
            val baseDensity = LocalDensity.current
            val locale = remember(localeTag) { Locale.forLanguageTag(localeTag) }
            val configuration = remember(baseConfiguration, locale) {
                Configuration(baseConfiguration).apply {
                    setLocale(locale)
                    setLocales(LocaleList(locale))
                }
            }
            val localizedContext = remember(baseContext, configuration) {
                baseContext.createConfigurationContext(configuration)
            }

            CompositionLocalProvider(
                LocalContext provides localizedContext,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(baseDensity.density, fontScale),
            ) {
                GradeyTheme {
                    Box(modifier = Modifier.width(width)) {
                        AbsencePredictorCard(onPlanAbsence = onPlanAbsence)
                    }
                }
            }
        }
    }

    private fun localizedString(resource: Int, localeTag: String): String {
        val locale = Locale.forLanguageTag(localeTag)
        val configuration = Configuration(context.resources.configuration).apply {
            setLocale(locale)
            setLocales(LocaleList(locale))
        }
        return context.createConfigurationContext(configuration).getString(resource)
    }

    private fun rangeNode(range: GradeTrendRange) = composeRule.onNodeWithTag(
        TODAY_RANGE_TEST_TAG_PREFIX + range.name,
        useUnmergedTree = true,
    )

    private companion object {
        const val TODAY_ACTION_PILL_TEST_TAG = "todayActionPill"
        val tabRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}

private fun SemanticsNodeInteraction.assertNoVisualOverflow(label: String): SemanticsNodeInteraction {
    val layoutResults = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
    val getLayoutResult = fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult]
    assertTrue(
        "$label must expose a text layout result",
        getLayoutResult.action?.invoke(layoutResults) == true,
    )
    val layoutResult = layoutResults.single()
    assertFalse(
        "$label must not be clipped or truncated " +
            "(width=${layoutResult.didOverflowWidth}, height=${layoutResult.didOverflowHeight}, " +
            "lines=${layoutResult.lineCount}, size=${layoutResult.size}, " +
            "paragraphWidth=${layoutResult.multiParagraph.width}, " +
            "lineRight=${layoutResult.getLineRight(0)}, " +
            "constraints=${layoutResult.layoutInput.constraints})",
        layoutResult.hasVisualOverflow,
    )
    return this
}
