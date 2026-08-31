package com.bukovinafilip.gradey.feature.subjects

import android.content.res.Configuration
import android.os.LocaleList
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
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
import com.bukovinafilip.gradey.domain.DemoData
import com.bukovinafilip.gradey.model.Subject
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
    fun subjectRowsGrowAndKeepCzechContentContainedAtTwoHundredPercentFontScale() {
        val longCzechSubject = DemoData.czech.copy(
            subjectInfo = DemoData.czech.subjectInfo.copy(
                name = "Český jazyk a literatura v evropském kontextu",
            ),
        )
        val subjects = listOf(DemoData.math, longCzechSubject)
        setSubjectRows(subjects = subjects, localeTag = "cs-CZ", fontScale = 2f, width = 320.dp)

        subjects.forEach { subject -> subjectRow(subject).performScrollTo().assertIsDisplayed() }
        val rowBounds = subjects.associateWith { subject ->
            subjectRow(subject).fetchSemanticsNode().boundsInRoot
        }
        val minimumHeightPx = 68f * context.resources.displayMetrics.density

        subjects.forEach { subject ->
            val bounds = checkNotNull(rowBounds[subject])
            val latestMark = subject.marks.last()
            val titleNode = subjectTitle(subject)
            val titleBounds = titleNode.fetchSemanticsNode().boundsInRoot
            val markCountBounds = composeRule.onNodeWithText(
                localizedMarkCount(subject.marks.size, "cs-CZ"),
                useUnmergedTree = true,
            ).fetchSemanticsNode().boundsInRoot
            val pillBounds = inlineMarkPill(latestMark.id).fetchSemanticsNode().boundsInRoot
            val pillTextBounds = composeRule.onNodeWithText(latestMark.markText, useUnmergedTree = true)
                .fetchSemanticsNode().boundsInRoot
            val summaryBounds = subjectSummary(subject).fetchSemanticsNode().boundsInRoot
            val absenceSummaryNode = subjectAbsenceSummary(subject)
            assertTrue("${subject.displayName} row must grow beyond its 68dp normal-scale minimum", bounds.height > minimumHeightPx)
            titleNode.assertNoTextTruncation("${subject.displayName} title")
            absenceSummaryNode.assertNoTextTruncation("${subject.displayName} absence summary")
            assertContained(
                parent = bounds,
                child = titleBounds,
                label = "${subject.displayName} title",
            )
            assertContained(
                parent = bounds,
                child = markCountBounds,
                label = "${subject.displayName} mark count",
            )
            assertContained(bounds, pillBounds, "${subject.displayName} latest-mark pill")
            assertContained(pillBounds, pillTextBounds, "${subject.displayName} latest-mark text")
            assertContained(bounds, summaryBounds, "${subject.displayName} summary")
            assertTrue(
                "${subject.displayName} latest-mark pill must grow beyond its 23dp normal-scale minimum",
                pillBounds.height > 23f * context.resources.displayMetrics.density,
            )
            listOf(
                "title" to titleBounds,
                "mark count" to markCountBounds,
                "latest-mark pill" to pillBounds,
            ).forEach { (label, childBounds) ->
                assertTrue(
                    "${subject.displayName} $label must not overlap the right-side summary",
                    !childBounds.overlaps(summaryBounds),
                )
            }
        }

        val orderedRows = rowBounds.values.sortedBy { it.top }
        assertTrue(
            "Adjacent subject rows must not overlap at 200% font scale",
            orderedRows.zipWithNext().all { (first, second) -> first.bottom <= second.top },
        )
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

    private fun setSubjectRows(
        subjects: List<Subject>,
        localeTag: String,
        fontScale: Float,
        width: androidx.compose.ui.unit.Dp,
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
                        SubjectsScreen(
                            subjects = subjects,
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

    private fun subjectRow(subject: Subject) = composeRule.onNodeWithTag(
        SUBJECT_ROW_TEST_TAG_PREFIX + subject.id,
        useUnmergedTree = true,
    )

    private fun inlineMarkPill(markID: String) = composeRule.onNodeWithTag(
        SUBJECT_INLINE_MARK_TEST_TAG_PREFIX + markID,
        useUnmergedTree = true,
    )

    private fun subjectTitle(subject: Subject) = composeRule.onNodeWithTag(
        SUBJECT_TITLE_TEST_TAG_PREFIX + subject.id,
        useUnmergedTree = true,
    )

    private fun subjectSummary(subject: Subject) = composeRule.onNodeWithTag(
        SUBJECT_SUMMARY_TEST_TAG_PREFIX + subject.id,
        useUnmergedTree = true,
    )

    private fun subjectAbsenceSummary(subject: Subject) = composeRule.onNodeWithTag(
        SUBJECT_ABSENCE_SUMMARY_TEST_TAG_PREFIX + subject.id,
        useUnmergedTree = true,
    )

    private fun localizedMarkCount(count: Int, localeTag: String): String {
        val locale = Locale.forLanguageTag(localeTag)
        val configuration = Configuration(context.resources.configuration).apply {
            setLocale(locale)
            setLocales(LocaleList(locale))
        }
        return context.createConfigurationContext(configuration).resources.getQuantityString(
            R.plurals.subject_mark_count,
            count,
            count,
        )
    }

    private fun assertContained(
        parent: androidx.compose.ui.geometry.Rect,
        child: androidx.compose.ui.geometry.Rect,
        label: String,
    ) {
        assertTrue(
            "$label must remain inside its subject row",
            child.left >= parent.left &&
                child.top >= parent.top &&
                child.right <= parent.right &&
                child.bottom <= parent.bottom,
        )
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertMinimumTarget() =
        assertHeightIsAtLeast(48.dp).assertWidthIsAtLeast(48.dp)

    private companion object {
        val tabRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}

private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertNoTextTruncation(label: String) {
    val layoutResults = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
    val getLayoutResult = fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult]
    assertTrue(
        "$label must expose a text layout result",
        getLayoutResult.action?.invoke(layoutResults) == true,
    )
    val layoutResult = layoutResults.single()
    assertFalse(
        "$label must not overflow " +
            "(width=${layoutResult.didOverflowWidth}, height=${layoutResult.didOverflowHeight}, " +
            "lines=${layoutResult.lineCount}, size=${layoutResult.size}, " +
            "paragraphWidth=${layoutResult.multiParagraph.width}, " +
            "constraints=${layoutResult.layoutInput.constraints})",
        layoutResult.hasVisualOverflow,
    )
    assertFalse(
        "$label must not be ellipsized",
        (0 until layoutResult.lineCount).any(layoutResult::isLineEllipsized),
    )
}
