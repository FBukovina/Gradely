package com.bukovinafilip.gradey.feature.login

import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bukovinafilip.gradey.ui.GradeyTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SchoolLoginStatusAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun asynchronousDirectoryFailureIsAPoliteLiveRegion() {
        val directoryError = mutableStateOf<String?>(null)
        composeRule.setContent {
            TestScreen(directoryErrorMessage = directoryError.value)
        }

        composeRule.onNodeWithText(DirectoryFailure).assertDoesNotExist()
        composeRule.runOnIdle { directoryError.value = DirectoryFailure }

        composeRule.onNodeWithText(DirectoryFailure)
            .performScrollTo()
            .assert(liveRegionMatcher(LiveRegionMode.Polite))
    }

    @Test
    fun asynchronousAuthenticationFailureIsAnAssertiveLiveRegion() {
        val authenticationError = mutableStateOf<String?>(null)
        composeRule.setContent {
            TestScreen(errorMessage = authenticationError.value)
        }

        composeRule.onNodeWithText(AuthenticationFailure).assertDoesNotExist()
        composeRule.runOnIdle { authenticationError.value = AuthenticationFailure }

        composeRule.onNodeWithText(AuthenticationFailure)
            .performScrollTo()
            .assert(liveRegionMatcher(LiveRegionMode.Assertive))
    }

    @Composable
    private fun TestScreen(
        directoryErrorMessage: String? = null,
        errorMessage: String? = null,
    ) {
        GradeyTheme {
            SchoolLoginScreen(
                isLoading = false,
                errorMessage = errorMessage,
                directoryErrorMessage = directoryErrorMessage,
                onLoadDirectory = {},
                onRetryDirectory = {},
                onLogin = { _, _, _ -> },
                onInputChanged = {},
                onOpenHelp = {},
                onOpenGitHub = {},
            )
        }
    }

    private fun liveRegionMatcher(mode: LiveRegionMode) =
        SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, mode)

    private companion object {
        const val DirectoryFailure = "Directory unavailable for accessibility test"
        const val AuthenticationFailure = "Authentication failed for accessibility test"
    }
}
