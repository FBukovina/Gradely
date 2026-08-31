package com.bukovinafilip.gradey.feature.timetable

import android.content.res.Configuration
import android.os.LocaleList
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableChange
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.Locale
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TimetableLessonDetailAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun populatedCzechDetailReflowsAndScrollsAtTwoHundredPercentFontScale() {
        setDetailSheet()

        val hero = composeRule.onNodeWithTag(
            TIMETABLE_DETAIL_HERO_TEST_TAG,
            useUnmergedTree = true,
        )
        val heroTitle = composeRule.onNodeWithTag(
            TIMETABLE_DETAIL_HERO_TITLE_TEST_TAG,
            useUnmergedTree = true,
        )
        heroTitle.assertNoTextVisualOverflow("lesson hero title")
        assertContained(
            parent = hero.fetchSemanticsNode().boundsInRoot,
            child = heroTitle.fetchSemanticsNode().boundsInRoot,
            label = "lesson hero title",
        )

        val lastRow = composeRule.onNodeWithTag(
            TIMETABLE_DETAIL_ROW_TEST_TAG_PREFIX + R.string.timetable_change_type,
            useUnmergedTree = true,
        )
        lastRow.assertIsNotDisplayed().performScrollTo().assertIsDisplayed()

        val lastLabel = composeRule.onNodeWithText(
            localizedString(R.string.timetable_change_type),
            useUnmergedTree = true,
        ).assertIsDisplayed()
        val lastValue = composeRule.onNodeWithText(
            LastChangeType,
            useUnmergedTree = true,
        ).assertIsDisplayed()
        lastLabel.assertNoTextVisualOverflow("last detail label")
        lastValue.assertNoTextVisualOverflow("last detail value")

        val scrollBounds = composeRule.onNodeWithTag(
            TIMETABLE_DETAIL_SCROLL_TEST_TAG,
            useUnmergedTree = true,
        ).fetchSemanticsNode().boundsInRoot
        val lastRowBounds = lastRow.fetchSemanticsNode().boundsInRoot
        val lastLabelBounds = lastLabel.fetchSemanticsNode().boundsInRoot
        val lastValueBounds = lastValue.fetchSemanticsNode().boundsInRoot
        assertContained(scrollBounds, lastRowBounds, "last populated detail row")
        assertContained(lastRowBounds, lastLabelBounds, "last detail label")
        assertContained(lastRowBounds, lastValueBounds, "last detail value")
        assertTrue(
            "The last detail label and value must not overlap",
            lastLabelBounds.bottom <= lastValueBounds.top,
        )
    }

    @Test
    fun twoCzechLessonRowsGrowWithoutOverlapAndRemainScrollableAtTwoHundredPercentFontScale() {
        setLessonList()

        val list = composeRule.onNodeWithTag(
            TIMETABLE_LESSONS_LIST_TEST_TAG,
            useUnmergedTree = true,
        )
        val firstRow = composeRule.onNodeWithTag(
            TIMETABLE_LESSON_ROW_TEST_TAG_PREFIX + MetadataOnlyLesson.id,
            useUnmergedTree = true,
        ).assertIsDisplayed()
        val firstCard = composeRule.onNodeWithTag(
            TIMETABLE_LESSON_CARD_TEST_TAG_PREFIX + MetadataOnlyLesson.id,
            useUnmergedTree = true,
        ).assertIsDisplayed()
        val secondRow = composeRule.onNodeWithTag(
            TIMETABLE_LESSON_ROW_TEST_TAG_PREFIX + PopulatedListLesson.id,
            useUnmergedTree = true,
        ).assertIsDisplayed()
        val secondCard = composeRule.onNodeWithTag(
            TIMETABLE_LESSON_CARD_TEST_TAG_PREFIX + PopulatedListLesson.id,
            useUnmergedTree = true,
        ).assertIsDisplayed()

        val firstRowBounds = firstRow.fetchSemanticsNode().boundsInRoot
        val firstCardBounds = firstCard.fetchSemanticsNode().boundsInRoot
        val secondRowBounds = secondRow.fetchSemanticsNode().boundsInRoot
        val secondCardBounds = secondCard.fetchSemanticsNode().boundsInRoot
        val displayDensity = context.resources.displayMetrics.density
        assertTrue(
            "The metadata-only row must grow beyond its normal 76dp minimum at 200% font scale",
            firstRowBounds.height > 76f * displayDensity,
        )
        assertTrue(
            "The populated row must grow beyond its normal 102dp minimum at 200% font scale",
            secondRowBounds.height > 102f * displayDensity,
        )
        assertTrue(
            "Consecutive lesson rows must not overlap",
            firstRowBounds.bottom <= secondRowBounds.top,
        )
        assertContained(firstRowBounds, firstCardBounds, "metadata-only lesson card")
        assertContained(secondRowBounds, secondCardBounds, "populated lesson card")

        assertTextsContained(
            parent = firstRowBounds,
            texts = listOf("1.", "8:00", "8:45"),
            label = "metadata-only lesson time rail",
        )
        assertTextsContained(
            parent = firstCardBounds,
            texts = listOf("FY", "Fyzika", "A1"),
            label = "metadata-only lesson card",
        )
        assertTextsContained(
            parent = secondRowBounds,
            texts = listOf("2.", "9:00", "9:45"),
            label = "populated lesson time rail",
        )
        assertTextsContained(
            parent = secondCardBounds,
            texts = listOf(
                "DĚ",
                "Dějepis",
                "B2",
                "Četba",
                localizedString(R.string.timetable_change_substitution),
                localizedString(R.string.timetable_detail_homework),
            ),
            label = "populated lesson card",
        )

        val initialSecondTop = secondRowBounds.top
        list.performScrollToIndex(1)
        val scrolledSecondBounds = secondRow.assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        assertTrue(
            "The lesson list must scroll to the last populated row",
            scrolledSecondBounds.top < initialSecondTop,
        )
        assertContained(
            parent = list.fetchSemanticsNode().boundsInRoot,
            child = scrolledSecondBounds,
            label = "last populated lesson row after scrolling",
        )
    }

    private fun setDetailSheet() {
        composeRule.setContent {
            val baseContext = LocalContext.current
            val baseConfiguration = LocalConfiguration.current
            val baseDensity = LocalDensity.current
            val locale = remember { Locale.forLanguageTag(CzechLocaleTag) }
            val configuration = remember(baseConfiguration, locale) {
                Configuration(baseConfiguration).apply {
                    fontScale = 2f
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
                LocalDensity provides Density(baseDensity.density, fontScale = 2f),
            ) {
                GradeyTheme {
                    Box(
                        modifier = Modifier
                            .width(320.dp)
                            .height(480.dp),
                    ) {
                        LessonDetailSheet(FullyPopulatedLesson)
                    }
                }
            }
        }
    }

    private fun setLessonList() {
        composeRule.setContent {
            val baseContext = LocalContext.current
            val baseConfiguration = LocalConfiguration.current
            val baseDensity = LocalDensity.current
            val locale = remember { Locale.forLanguageTag(CzechLocaleTag) }
            val configuration = remember(baseConfiguration, locale) {
                Configuration(baseConfiguration).apply {
                    fontScale = 2f
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
                LocalDensity provides Density(baseDensity.density, fontScale = 2f),
            ) {
                GradeyTheme {
                    Box(
                        modifier = Modifier
                            .width(320.dp)
                            .height(360.dp),
                    ) {
                        LessonsList(
                            day = TwoLessonDay,
                            isLoaded = true,
                            onOpenLesson = {},
                        )
                    }
                }
            }
        }
    }

    private fun SemanticsNodeInteraction.assertNoTextVisualOverflow(label: String) {
        val layoutResults = mutableListOf<TextLayoutResult>()
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

    private fun assertTextsContained(
        parent: Rect,
        texts: List<String>,
        label: String,
    ) {
        texts.forEach { text ->
            val node = composeRule.onNodeWithText(text, useUnmergedTree = true)
            node.assertNoVerticalTextOverflow("$label text '$text'")
            assertContained(parent, node.fetchSemanticsNode().boundsInRoot, "$label text '$text'")
        }
    }

    private fun SemanticsNodeInteraction.assertNoVerticalTextOverflow(label: String) {
        val layoutResults = mutableListOf<TextLayoutResult>()
        val getLayoutResult = fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult]
        assertTrue(
            "$label must expose a text layout result",
            getLayoutResult.action?.invoke(layoutResults) == true,
        )
        val layoutResult = layoutResults.single()
        assertFalse(
            "$label must not overflow vertically " +
                "(width=${layoutResult.didOverflowWidth}, height=${layoutResult.didOverflowHeight}, " +
                "lines=${layoutResult.lineCount}, size=${layoutResult.size}, " +
                "paragraphWidth=${layoutResult.multiParagraph.width}, " +
                "constraints=${layoutResult.layoutInput.constraints})",
            layoutResult.didOverflowHeight,
        )
        assertFalse(
            "$label must not be ellipsized",
            (0 until layoutResult.lineCount).any(layoutResult::isLineEllipsized),
        )
    }

    private fun assertContained(parent: Rect, child: Rect, label: String) {
        assertTrue(
            "$label must remain within its parent bounds (parent=$parent, child=$child)",
            child.left >= parent.left &&
                child.top >= parent.top &&
                child.right <= parent.right &&
                child.bottom <= parent.bottom,
        )
    }

    private fun localizedString(resourceID: Int): String {
        val locale = Locale.forLanguageTag(CzechLocaleTag)
        val configuration = Configuration(context.resources.configuration).apply {
            setLocale(locale)
            setLocales(LocaleList(locale))
        }
        return context.createConfigurationContext(configuration).getString(resourceID)
    }

    private companion object {
        const val CzechLocaleTag = "cs-CZ"
        const val LastChangeType = "Přesunutá výuka"

        val MetadataOnlyLesson = ScheduledLesson(
            id = "adaptive-metadata-row",
            hour = TimetableHour(
                id = "1",
                caption = "1.",
                beginTime = "08:00",
                endTime = "08:45",
            ),
            subjectName = "Fyzika",
            subjectAbbrev = "FY",
            teacherName = null,
            teacherAbbrev = null,
            roomAbbrev = "A1",
            roomName = null,
            groups = emptyList(),
            theme = null,
            hasHomework = false,
        )

        val PopulatedListLesson = ScheduledLesson(
            id = "adaptive-populated-row",
            hour = TimetableHour(
                id = "2",
                caption = "2.",
                beginTime = "09:00",
                endTime = "09:45",
            ),
            subjectName = "Dějepis",
            subjectAbbrev = "DĚ",
            teacherName = null,
            teacherAbbrev = null,
            roomAbbrev = "B2",
            roomName = null,
            groups = emptyList(),
            theme = "Četba",
            hasHomework = true,
            changeDescription = "Výuku vede zastupující učitel.",
            changeKind = LessonChangeKind.SUBSTITUTION,
        )

        val TwoLessonDay = ScheduledDay(
            id = "adaptive-two-lesson-day",
            date = "2026-08-31",
            dayOfWeek = 1,
            dayDescription = "",
            dayType = "schoolday",
            lessons = listOf(MetadataOnlyLesson, PopulatedListLesson),
            isToday = true,
        )

        val FullyPopulatedLesson = ScheduledLesson(
            id = "adaptive-detail-lesson",
            hour = TimetableHour(
                id = "1",
                caption = "1.",
                beginTime = "08:00",
                endTime = "08:45",
            ),
            subjectName = "Český jazyk",
            subjectAbbrev = "ČJ",
            teacherName = "Mgr. Jana Nováková",
            teacherAbbrev = "Nov",
            roomAbbrev = "U12",
            roomName = "Učebna českého jazyka",
            groups = listOf("Skupina A", "Skupina B"),
            theme = "Literatura národního obrození",
            hasHomework = true,
            changeDescription = "Výuka byla přesunuta kvůli školní akci.",
            changeKind = LessonChangeKind.SUBSTITUTION,
            change = TimetableChange(
                changeType = "substitution",
                description = "Výuka byla přesunuta kvůli školní akci.",
                changeSubject = "Český jazyk a literatura",
                day = "pondělí 1. září",
                hours = "1.–2. hodina",
                time = "08:00–09:40",
                typeAbbrev = "PŘS",
                typeName = LastChangeType,
            ),
        )
    }
}
