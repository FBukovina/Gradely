package com.bukovinafilip.gradey.feature.login

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.espresso.Espresso.pressBack
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SchoolLoginBackInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun systemBackUsesScreenCallbackWhenIdle() {
        val backCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                SchoolLoginScreen(
                    isLoading = false,
                    onLoadDirectory = {},
                    onRetryDirectory = {},
                    onLogin = { _, _, _ -> },
                    onInputChanged = {},
                    onOpenHelp = {},
                    onOpenGitHub = {},
                    onBack = { backCount.incrementAndGet() },
                )
            }
        }

        pressBack()

        composeRule.runOnIdle { assertEquals(1, backCount.get()) }
    }

    @Test
    fun systemBackCancelsAnActiveLoginWithoutLeavingTheScreen() {
        val isLoading = mutableStateOf(true)
        val backCount = AtomicInteger(0)
        val cancelCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                SchoolLoginScreen(
                    isLoading = isLoading.value,
                    onLoadDirectory = {},
                    onRetryDirectory = {},
                    onLogin = { _, _, _ -> },
                    onCancelLogin = { cancelCount.incrementAndGet() },
                    onInputChanged = {},
                    onOpenHelp = {},
                    onOpenGitHub = {},
                    onBack = { backCount.incrementAndGet() },
                )
            }
        }

        pressBack()

        composeRule.runOnIdle {
            assertEquals(1, cancelCount.get())
            assertEquals(0, backCount.get())
        }
        composeRule.onNodeWithText(context.getString(R.string.login_title))
            .assertIsDisplayed()
    }

    @Test
    fun systemBackIsConsumedWhileUncancelableWorkIsActive() {
        val backCount = AtomicInteger(0)
        composeRule.setContent {
            GradeyTheme {
                SchoolLoginScreen(
                    isLoading = true,
                    onLoadDirectory = {},
                    onRetryDirectory = {},
                    onLogin = { _, _, _ -> },
                    onInputChanged = {},
                    onOpenHelp = {},
                    onOpenGitHub = {},
                    onBack = { backCount.incrementAndGet() },
                )
            }
        }

        pressBack()

        composeRule.runOnIdle { assertEquals(0, backCount.get()) }
        composeRule.onNodeWithText(context.getString(R.string.login_title))
            .assertIsDisplayed()
    }
}
