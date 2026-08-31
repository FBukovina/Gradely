package com.bukovinafilip.gradey.feature.timetable

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.dp
import androidx.test.espresso.Espresso.pressBack
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bukovinafilip.gradey.model.LessonChangeKind
import com.bukovinafilip.gradey.model.ScheduledDay
import com.bukovinafilip.gradey.model.ScheduledLesson
import com.bukovinafilip.gradey.model.TimetableChange
import com.bukovinafilip.gradey.model.TimetableHour
import com.bukovinafilip.gradey.model.TimetableWeek
import com.bukovinafilip.gradey.ui.GradeyTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TimetableLessonDrillInInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun lessonCardOpensMatchingDetailAndSystemBackDismissesIt() {
        composeRule.setContent {
            GradeyTheme {
                TimetableScreen(
                    week = TestWeek,
                    isRefreshing = false,
                    errorMessage = null,
                    onRefresh = {},
                    onChangeWeek = {},
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                )
            }
        }

        lessonCard()
            .performScrollTo()
            .assertIsDisplayed()
            .assert(ButtonRoleMatcher)
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
            .performClick()

        composeRule.onNodeWithTag(
            TIMETABLE_DETAIL_HERO_TITLE_TEST_TAG,
            useUnmergedTree = true,
        )
            .assertIsDisplayed()
            .assertTextEquals(TestSubjectName)
        composeRule.onNodeWithTag(
            TIMETABLE_DETAIL_ROW_TEST_TAG_PREFIX + R.string.timetable_change_type,
            useUnmergedTree = true,
        ).assertIsDisplayed()
        composeRule.onNodeWithText(DetailOnlyChangeType, useUnmergedTree = true)
            .assertIsDisplayed()

        pressBack()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithTag(
                TIMETABLE_DETAIL_HERO_TITLE_TEST_TAG,
                useUnmergedTree = true,
            ).fetchSemanticsNodes().isEmpty()
        }

        lessonCard().performScrollTo().assertIsDisplayed()
    }

    private fun lessonCard() = composeRule.onNodeWithTag(
        TIMETABLE_LESSON_CARD_TEST_TAG_PREFIX + TestLesson.id,
        useUnmergedTree = true,
    )

    private companion object {
        const val TestSubjectName = "Interaction Physics"
        const val DetailOnlyChangeType = "Detail-only substitution"

        val TestHour = TimetableHour(
            id = "interaction-hour",
            caption = "1.",
            beginTime = "08:00",
            endTime = "08:45",
        )
        val TestLesson = ScheduledLesson(
            id = "interaction-lesson",
            hour = TestHour,
            subjectName = TestSubjectName,
            subjectAbbrev = "IP",
            teacherName = "Dr. Device Test",
            teacherAbbrev = "DDT",
            roomAbbrev = "D42",
            roomName = "Device Lab",
            groups = listOf("Group A"),
            theme = "Interaction state",
            hasHomework = true,
            changeDescription = "The lesson uses a substitute teacher.",
            changeKind = LessonChangeKind.SUBSTITUTION,
            change = TimetableChange(
                changeType = "substitution",
                typeAbbrev = "SUB",
                typeName = DetailOnlyChangeType,
            ),
        )
        val TestWeek = TimetableWeek(
            weekStart = "2030-01-07",
            days = listOf(
                ScheduledDay(
                    id = "interaction-day",
                    date = "2030-01-07",
                    dayOfWeek = 1,
                    dayDescription = "",
                    dayType = "schoolday",
                    lessons = listOf(TestLesson),
                    isToday = false,
                ),
            ),
            hours = listOf(TestHour),
        )
        val ButtonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}
