package com.bukovinafilip.gradey.navigation

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SignedInNavHostTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun primaryTabsSaveAndRestoreTheirEntryState() {
        setNavigationContent()

        click("today-increment")
        click("today-subjects")
        click("subjects-increment")
        click("subjects-today")
        composeRule.onNodeWithTag("today-state").assertTextEquals("Today 1")

        click("today-subjects")
        composeRule.onNodeWithTag("subjects-state").assertTextEquals("Subjects 1")
    }

    @Test
    fun accountPushesSupportAndBackReturnsToAccount() {
        setNavigationContent()

        click("today-account")
        click("account-support")
        composeRule.onNodeWithTag("support-screen").assertIsDisplayed()

        click("support-back")
        composeRule.onNodeWithTag("account-screen").assertIsDisplayed()
    }

    @Test
    fun primaryTabPushesGradeyAiAndCloseReturnsToThatTab() {
        setNavigationContent()

        click("today-subjects")
        click("subjects-increment")
        click("subjects-ai")
        composeRule.onNodeWithTag("ai-screen").assertIsDisplayed()

        click("ai-close")
        composeRule.onNodeWithTag("subjects-state").assertTextEquals("Subjects 1")
    }

    @Test
    fun gradeyAiSupportReplacementBuildsSupportAboveAccount() {
        setNavigationContent()

        click("today-ai")
        click("ai-support")
        composeRule.onNodeWithTag("support-screen").assertIsDisplayed()

        click("support-back")
        composeRule.onNodeWithTag("account-screen").assertIsDisplayed()
    }

    @Test
    fun resetClearsSavedPrimaryStateAndCreatesFreshTodayRoot() {
        setNavigationContent()

        click("today-increment")
        click("today-subjects")
        click("subjects-increment")
        click("subjects-timetable")
        click("timetable-reset")
        composeRule.onNodeWithTag("today-state").assertTextEquals("Today 0")

        click("today-subjects")
        composeRule.onNodeWithTag("subjects-state").assertTextEquals("Subjects 0")
    }

    @Test
    fun hidingMealsFromItsAccountPresentationResetsToFreshToday() {
        setNavigationContent()

        click("today-increment")
        click("today-meals")
        click("meals-increment")
        click("meals-account")
        click("account-hide-meals")

        composeRule.onNodeWithTag("today-state").assertTextEquals("Today 0")
    }

    @Test
    fun identityBoundaryResetDismissesSupportAndClearsPrimaryState() {
        setNavigationContent()

        click("today-increment")
        click("today-account")
        click("account-support")
        click("support-reset")

        composeRule.onNodeWithTag("today-state").assertTextEquals("Today 0")
    }

    private fun setNavigationContent() {
        composeRule.setContent {
            val navController = rememberNavController()
            SignedInNavHost(
                navController = navController,
                todayContent = {
                    PrimaryScreen(
                        name = "Today",
                        actions = listOf(
                            "today-subjects" to {
                                navController.navigateToMainDestination(MainDestination.SUBJECTS)
                            },
                            "today-account" to {
                                navController.navigateToMainDestination(MainDestination.ACCOUNT)
                            },
                            "today-ai" to {
                                navController.navigateToMainDestination(MainDestination.GRADEY_AI)
                            },
                            "today-meals" to {
                                navController.navigateToMainDestination(MainDestination.MEALS)
                            },
                        ),
                    )
                },
                subjectsContent = {
                    PrimaryScreen(
                        name = "Subjects",
                        actions = listOf(
                            "subjects-today" to {
                                navController.navigateToMainDestination(MainDestination.TODAY)
                            },
                            "subjects-timetable" to {
                                navController.navigateToMainDestination(MainDestination.TIMETABLE)
                            },
                            "subjects-ai" to {
                                navController.navigateToMainDestination(MainDestination.GRADEY_AI)
                            },
                        ),
                    )
                },
                absenceContent = { Text("Absence", Modifier.testTag("absence-screen")) },
                timetableContent = {
                    Column {
                        Text("Timetable", Modifier.testTag("timetable-screen"))
                        TaggedButton("timetable-reset") { navController.resetToToday() }
                    }
                },
                mealsContent = {
                    PrimaryScreen(
                        name = "Meals",
                        actions = listOf(
                            "meals-account" to {
                                navController.navigateToMainDestination(MainDestination.ACCOUNT)
                            },
                        ),
                    )
                },
                accountContent = {
                    Column {
                        Text("Account", Modifier.testTag("account-screen"))
                        TaggedButton("account-support") {
                            navController.navigateToMainDestination(MainDestination.SUPPORT)
                        }
                        TaggedButton("account-hide-meals") {
                            val presentingDestination = MainDestination.fromRoute(
                                navController.previousBackStackEntry?.destination?.route,
                            )
                            if (presentingDestination == MainDestination.MEALS) {
                                navController.resetToToday()
                            }
                        }
                    }
                },
                supportContent = {
                    Column {
                        Text("Support", Modifier.testTag("support-screen"))
                        TaggedButton("support-back") { navController.popBackStack() }
                        TaggedButton("support-reset") { navController.resetToToday() }
                    }
                },
                gradeyAiContent = {
                    Column {
                        Text("Gradey AI", Modifier.testTag("ai-screen"))
                        TaggedButton("ai-close") { navController.popBackStack() }
                        TaggedButton("ai-account") {
                            navController.navigateFromGradeyAiToAccount()
                        }
                        TaggedButton("ai-support") {
                            navController.navigateFromGradeyAiToSupport()
                        }
                    }
                },
            )
        }
    }

    private fun click(tag: String) {
        composeRule.onNodeWithTag(tag).assertIsDisplayed().performClick()
    }
}

@Composable
private fun PrimaryScreen(
    name: String,
    actions: List<Pair<String, () -> Unit>>,
) {
    var count by rememberSaveable { mutableIntStateOf(0) }
    val tagPrefix = name.lowercase()
    Column {
        Text("$name $count", Modifier.testTag("$tagPrefix-state"))
        TaggedButton("$tagPrefix-increment") { count += 1 }
        actions.forEach { (tag, action) -> TaggedButton(tag, action) }
    }
}

@Composable
private fun TaggedButton(tag: String, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.testTag(tag)) {
        Text(tag)
    }
}
