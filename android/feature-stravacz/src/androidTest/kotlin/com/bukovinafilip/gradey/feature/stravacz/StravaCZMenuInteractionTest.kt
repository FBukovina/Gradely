package com.bukovinafilip.gradey.feature.stravacz

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.runtime.mutableStateOf
import androidx.test.espresso.Espresso.pressBack
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMealType
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZMenuDay
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StravaCZMenuInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun directOrderAndCancelEmitExactMealArguments() {
        val mutations = CopyOnWriteArrayList<Pair<StravaCZMeal, Boolean>>()
        setScreen(
            menu = DirectActionsMenu,
            onSetMeal = { meal, ordered -> mutations += meal to ordered },
        )

        mealAction(OrderedMeal).performScrollTo().assertIsEnabled().performClick()
        mealAction(DirectMeal).performScrollTo().assertIsEnabled().performClick()

        composeRule.runOnIdle {
            assertEquals(
                listOf(OrderedMeal to false, DirectMeal to true),
                mutations.toList(),
            )
        }
    }

    @Test
    fun submittingAnyMealDisablesEveryMealActionAndSuppressesCallbacks() {
        val mutations = CopyOnWriteArrayList<Pair<StravaCZMeal, Boolean>>()
        setScreen(
            menu = DirectActionsMenu,
            submittingMealID = DirectMeal.id,
            onSetMeal = { meal, ordered -> mutations += meal to ordered },
        )

        mealAction(DirectMeal)
            .performScrollTo()
            .assertIsNotEnabled()
            .performClick()
        mealAction(OrderedMeal)
            .performScrollTo()
            .assertIsNotEnabled()
            .performClick()

        assertNoMutations(mutations)
    }

    @Test
    fun refreshingDisablesEveryMealActionAndSuppressesCallbacks() {
        val mutations = CopyOnWriteArrayList<Pair<StravaCZMeal, Boolean>>()
        setScreen(
            menu = DirectActionsMenu,
            isRefreshing = { true },
            onSetMeal = { meal, ordered -> mutations += meal to ordered },
        )

        mealAction(DirectMeal).performScrollTo().assertIsNotEnabled().performClick()
        mealAction(OrderedMeal).performScrollTo().assertIsNotEnabled().performClick()

        assertNoMutations(mutations)
    }

    @Test
    fun replacementConfirmationDisablesIfRefreshBeginsWhileDialogIsOpen() {
        val mutations = CopyOnWriteArrayList<Pair<StravaCZMeal, Boolean>>()
        val refreshing = mutableStateOf(false)
        setScreen(
            menu = ReplacementMenu,
            isRefreshing = { refreshing.value },
            onSetMeal = { meal, ordered -> mutations += meal to ordered },
        )

        openReplacementDialog()
        composeRule.runOnIdle { refreshing.value = true }
        composeRule.onNodeWithText(context.getString(R.string.stravacz_replace_confirm))
            .assertIsNotEnabled()
            .performClick()

        replacementDialogTitle().assertIsDisplayed()
        assertNoMutations(mutations)
    }

    @Test
    fun replacementRequiresConfirmationAndCancelBackNeverMutate() {
        val mutations = CopyOnWriteArrayList<Pair<StravaCZMeal, Boolean>>()
        setScreen(
            menu = ReplacementMenu,
            onSetMeal = { meal, ordered -> mutations += meal to ordered },
        )

        openReplacementDialog()
        assertNoMutations(mutations)
        composeRule.onNodeWithText(context.getString(R.string.stravacz_cancel)).performClick()
        replacementDialogTitle().assertDoesNotExist()
        assertNoMutations(mutations)

        openReplacementDialog()
        pressBack()
        composeRule.waitForIdle()
        replacementDialogTitle().assertDoesNotExist()
        assertNoMutations(mutations)

        openReplacementDialog()
        composeRule.onNodeWithText(context.getString(R.string.stravacz_replace_confirm))
            .assertIsDisplayed()
            .performClick()

        replacementDialogTitle().assertDoesNotExist()
        composeRule.runOnIdle {
            assertEquals(listOf(ReplacementMeal to true), mutations.toList())
        }
    }

    @Test
    fun disconnectRequiresConfirmationAndCancelBackNeverDisconnect() {
        val disconnectCount = AtomicInteger(0)
        setScreen(
            menu = ReplacementMenu,
            onDisconnect = { disconnectCount.incrementAndGet() },
        )

        openDisconnectDialog()
        assertEquals(0, disconnectCount.get())
        composeRule.onNodeWithText(context.getString(R.string.stravacz_cancel)).performClick()
        disconnectDialogTitle().assertDoesNotExist()
        assertEquals(0, disconnectCount.get())

        openDisconnectDialog()
        pressBack()
        composeRule.waitForIdle()
        disconnectDialogTitle().assertDoesNotExist()
        assertEquals(0, disconnectCount.get())

        openDisconnectDialog()
        composeRule.onNodeWithText(context.getString(R.string.stravacz_confirm_disconnect))
            .assertIsDisplayed()
            .performClick()

        disconnectDialogTitle().assertDoesNotExist()
        composeRule.runOnIdle { assertEquals(1, disconnectCount.get()) }
    }

    private fun setScreen(
        menu: StravaCZMenu,
        submittingMealID: Int? = null,
        isRefreshing: () -> Boolean = { false },
        onSetMeal: (StravaCZMeal, Boolean) -> Unit = { _, _ -> },
        onDisconnect: () -> Unit = {},
    ) {
        composeRule.setContent {
            GradeyTheme {
                StravaCZScreen(
                    session = TestSession,
                    menu = menu,
                    isLoading = false,
                    isRefreshing = isRefreshing(),
                    submittingMealID = submittingMealID,
                    errorMessage = null,
                    onConnect = { _, _, _ -> },
                    onRefresh = {},
                    onSetMeal = onSetMeal,
                    onDisconnect = onDisconnect,
                    onOpenAccount = {},
                    onOpenGradeyTools = {},
                )
            }
        }
    }

    private fun openReplacementDialog() {
        mealAction(ReplacementMeal).performScrollTo().assertIsEnabled().performClick()
        replacementDialogTitle().assertIsDisplayed()
    }

    private fun openDisconnectDialog() {
        composeRule.onNodeWithContentDescription(context.getString(R.string.stravacz_disconnect))
            .assertIsDisplayed()
            .assertIsEnabled()
            .performClick()
        disconnectDialogTitle().assertIsDisplayed()
    }

    private fun mealAction(meal: StravaCZMeal) = composeRule.onNodeWithTag(
        "$STRAVACZ_MEAL_ACTION_TEST_TAG_PREFIX${meal.dateKey}:${meal.id}",
    )

    private fun replacementDialogTitle() =
        composeRule.onNodeWithText(context.getString(R.string.stravacz_replace_title))

    private fun disconnectDialogTitle() =
        composeRule.onNodeWithText(context.getString(R.string.stravacz_disconnect_title))

    private fun assertNoMutations(mutations: List<Pair<StravaCZMeal, Boolean>>) {
        composeRule.runOnIdle {
            assertEquals(emptyList<Pair<StravaCZMeal, Boolean>>(), mutations.toList())
        }
    }

    private companion object {
        const val FirstDate = "2026-09-01"
        const val SecondDate = "2026-09-02"

        val TestSession = StravaCZStoredSession(
            sessionID = "session",
            serviceURL = "https://example.test",
            canteenNumber = "1234",
            username = "student",
            fullName = "Test Student",
            balance = 500.0,
        )
        val OrderedMeal = StravaCZMeal(
            id = 1,
            dateKey = FirstDate,
            type = StravaCZMealType.MAIN,
            name = "Already ordered meal",
            ordered = true,
        )
        val ReplacementMeal = StravaCZMeal(
            id = 2,
            dateKey = FirstDate,
            type = StravaCZMealType.MAIN,
            name = "Replacement meal",
        )
        val DirectMeal = StravaCZMeal(
            id = 3,
            dateKey = SecondDate,
            type = StravaCZMealType.MAIN,
            name = "Direct order meal",
        )
        val ReplacementMenu = StravaCZMenu(
            days = listOf(
                StravaCZMenuDay(
                    id = "first-day",
                    title = "Tuesday",
                    date = FirstDate,
                    ordered = true,
                    meals = listOf(OrderedMeal, ReplacementMeal),
                ),
            ),
        )
        val DirectActionsMenu = StravaCZMenu(
            days = listOf(
                StravaCZMenuDay(
                    id = "first-day",
                    title = "Tuesday",
                    date = FirstDate,
                    ordered = true,
                    meals = listOf(OrderedMeal),
                ),
                StravaCZMenuDay(
                    id = "second-day",
                    title = "Wednesday",
                    date = SecondDate,
                    meals = listOf(DirectMeal),
                ),
            ),
        )
    }
}
