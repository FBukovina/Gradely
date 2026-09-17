package com.bukovinafilip.gradey.feature.today

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TodayMealsVisibilityInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun enabledMealsSettingShowsLunchCardAndOpensMealsExactlyOnce() {
        val opens = AtomicInteger(0)
        setScreen(showMealsCard = true, onOpenMeals = { opens.incrementAndGet() })

        composeRule.onNodeWithTag(TODAY_LUNCH_CARD_TEST_TAG, useUnmergedTree = true)
            .performScrollTo()
            .assertIsDisplayed()
        composeRule.onNodeWithTag(TODAY_LUNCH_ACTION_TEST_TAG, useUnmergedTree = true)
            .assertIsDisplayed()
            .performClick()

        composeRule.runOnIdle { assertEquals(1, opens.get()) }
    }

    @Test
    fun disabledMealsSettingOmitsEntireLunchCardAndCannotOpenMeals() {
        val opens = AtomicInteger(0)
        setScreen(showMealsCard = false, onOpenMeals = { opens.incrementAndGet() })

        composeRule.onNodeWithTag(TODAY_LUNCH_CARD_TEST_TAG, useUnmergedTree = true).assertDoesNotExist()
        composeRule.onNodeWithTag(TODAY_LUNCH_ACTION_TEST_TAG, useUnmergedTree = true).assertDoesNotExist()
        composeRule.onNodeWithText(context.getString(R.string.today_meals_not_connected)).assertDoesNotExist()
        composeRule.runOnIdle { assertEquals(0, opens.get()) }
    }

    private fun setScreen(
        showMealsCard: Boolean,
        onOpenMeals: () -> Unit,
    ) {
        composeRule.setContent {
            GradeyTheme {
                TodayScreen(
                    dashboard = DashboardData(MarksResponse()),
                    absence = AbsenceResponse(),
                    timetable = null,
                    stravaMenu = null,
                    isMealsConnected = false,
                    showMealsCard = showMealsCard,
                    isRefreshing = false,
                    onRefresh = {},
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                    onOpenMarks = {},
                    onOpenAbsence = {},
                    onOpenTimetable = {},
                    onOpenMeals = onOpenMeals,
                    onActivateLinkedAccount = {},
                    onReconnectPrefill = { null },
                    onReconnectLinkedAccount = { _, _, _, _ -> null },
                )
            }
        }
    }
}
