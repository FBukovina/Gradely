package com.bukovinafilip.gradey.feature.absence

import android.content.res.Configuration
import android.os.LocaleList
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AbsenceModePickerAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun optionsExposeGroupedTabSelectionMinimumTargetsAndCallbacks() {
        val callbackCount = AtomicInteger(0)
        val lastSelection = AtomicReference<AbsenceMode>()
        setPicker(
            width = 300.dp,
            onSelect = { mode ->
                callbackCount.incrementAndGet()
                lastSelection.set(mode)
            },
        )

        composeRule.onNodeWithTag(ABSENCE_MODE_PICKER_TEST_TAG, useUnmergedTree = true)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.SelectableGroup))
            .assertHeightIsAtLeast(48.dp)

        AbsenceMode.entries.forEach { mode ->
            modeNode(mode)
                .assert(tabRoleMatcher)
                .assertHeightIsAtLeast(48.dp)
                .assertWidthIsAtLeast(48.dp)
        }
        modeNode(AbsenceMode.Subjects).assertIsSelected()
        modeNode(AbsenceMode.Days).assertIsNotSelected()

        modeNode(AbsenceMode.Months).performClick().assertIsSelected()
        modeNode(AbsenceMode.Subjects).assertIsNotSelected()

        composeRule.runOnIdle {
            assertEquals(1, callbackCount.get())
            assertEquals(AbsenceMode.Months, lastSelection.get())
        }
    }

    @Test
    fun englishLabelsStayDisplayedAndSeparateAtCompactWidthAndLargeFont() {
        assertCompactLargeFontLayout(localeTag = "en")
    }

    @Test
    fun czechLabelsStayDisplayedAndSeparateAtCompactWidthAndLargeFont() {
        assertCompactLargeFontLayout(localeTag = "cs")
    }

    private fun assertCompactLargeFontLayout(localeTag: String) {
        setPicker(localeTag = localeTag, fontScale = 2f, width = 220.dp)

        val labels = listOf(
            localizedString(R.string.absence_segment_subjects, localeTag),
            localizedString(R.string.absence_segment_days, localeTag),
            localizedString(R.string.absence_segment_months, localeTag),
        )
        val labelNodes = labels.map { label ->
            composeRule.onNodeWithText(label, useUnmergedTree = true)
                .assertIsDisplayed()
        }
        val labelBounds = labelNodes.map { it.fetchSemanticsNode().boundsInRoot }
        val lineCounts = labelNodes.map(SemanticsNodeInteraction::assertNoVisualOverflow)
        val optionBounds = AbsenceMode.entries.map { mode ->
            modeNode(mode)
                .assertIsDisplayed()
                .assertHeightIsAtLeast(48.dp)
                .assertWidthIsAtLeast(48.dp)
                .fetchSemanticsNode().boundsInRoot
        }

        optionBounds.zipWithNext().forEach { (left, right) ->
            assertTrue("Mode targets must not overlap", left.right <= right.left)
        }
        labelBounds.zipWithNext().forEach { (left, right) ->
            assertTrue("Mode labels must not overlap", left.right <= right.left)
        }
        labelBounds.zip(optionBounds).forEach { (label, option) ->
            assertTrue(
                "Mode label must remain inside its target",
                label.left >= option.left &&
                    label.right <= option.right &&
                    label.top >= option.top &&
                    label.bottom <= option.bottom,
            )
        }
        if (lineCounts.any { it > 1 }) {
            val pickerHeight = composeRule.onNodeWithTag(
                ABSENCE_MODE_PICKER_TEST_TAG,
                useUnmergedTree = true,
            ).fetchSemanticsNode().boundsInRoot.height
            val minimumHeightPx = 48f * context.resources.displayMetrics.density
            assertTrue("The mode track must grow when a label wraps", pickerHeight > minimumHeightPx)
        }
    }

    private fun setPicker(
        localeTag: String = "en",
        fontScale: Float = 1f,
        width: Dp,
        onSelect: (AbsenceMode) -> Unit = {},
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
            var selected by remember { mutableStateOf(AbsenceMode.Subjects) }

            CompositionLocalProvider(
                LocalContext provides localizedContext,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(baseDensity.density, fontScale),
            ) {
                GradeyTheme {
                    Box(modifier = Modifier.width(width)) {
                        AbsenceModePicker(
                            selected = selected,
                            onSelect = { mode ->
                                selected = mode
                                onSelect(mode)
                            },
                        )
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

    private fun modeNode(mode: AbsenceMode) = composeRule.onNodeWithTag(
        ABSENCE_MODE_TEST_TAG_PREFIX + mode.name,
        useUnmergedTree = true,
    )

    private companion object {
        val tabRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
    }
}

private fun SemanticsNodeInteraction.assertNoVisualOverflow(): Int {
    val layoutResults = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
    val getLayoutResult = fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult]
    assertTrue(
        "The mode label must expose a text layout result",
        getLayoutResult.action?.invoke(layoutResults) == true,
    )
    val layoutResult = layoutResults.single()
    assertFalse("The mode label must not be clipped or truncated", layoutResult.hasVisualOverflow)
    return layoutResult.lineCount
}
