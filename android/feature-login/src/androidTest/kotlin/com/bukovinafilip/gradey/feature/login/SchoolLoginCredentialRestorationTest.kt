package com.bukovinafilip.gradey.feature.login

import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.text.AnnotatedString
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SchoolLoginCredentialRestorationTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun restorationPreservesSafeProgressButClearsAndHidesPasswordWithoutSubmitting() {
        val loginCount = AtomicInteger(0)
        val submittedCredentials = AtomicReference<Triple<String, String, String>>()
        val restorationTester = StateRestorationTester(composeRule)
        restorationTester.setContent {
            TestScreen(
                seed = LoginSeed("reconnect:school-a", InitialURL, InitialName, InitialUsername),
                onLogin = { school, username, password ->
                    loginCount.incrementAndGet()
                    submittedCredentials.set(Triple(school, username, password))
                },
            )
        }

        replace(SCHOOL_LOGIN_URL_FIELD_TEST_TAG, EditedURL)
        replace(SCHOOL_LOGIN_SEARCH_FIELD_TEST_TAG, EditedName)
        replace(SCHOOL_LOGIN_USERNAME_FIELD_TEST_TAG, EditedUsername)
        input(SCHOOL_LOGIN_PASSWORD_FIELD_TEST_TAG, Password)
        composeRule.onNodeWithTag(SCHOOL_LOGIN_PASSWORD_VISIBILITY_TEST_TAG)
            .performClick()
            .assertContentDescriptionEquals(context.getString(R.string.login_hide_password))

        restorationTester.emulateSavedInstanceStateRestore()

        assertText(SCHOOL_LOGIN_URL_FIELD_TEST_TAG, EditedURL)
        assertText(SCHOOL_LOGIN_SEARCH_FIELD_TEST_TAG, EditedName)
        assertText(SCHOOL_LOGIN_USERNAME_FIELD_TEST_TAG, EditedUsername)
        assertText(SCHOOL_LOGIN_PASSWORD_FIELD_TEST_TAG, "")
        composeRule.onNodeWithTag(SCHOOL_LOGIN_PASSWORD_VISIBILITY_TEST_TAG)
            .assertContentDescriptionEquals(context.getString(R.string.login_show_password))
        composeRule.onNodeWithTag(SCHOOL_LOGIN_CONNECT_BUTTON_TEST_TAG)
            .performScrollTo()
            .performClick()
        assertEquals(0, loginCount.get())
        assertNull(submittedCredentials.get())
    }

    @Test
    fun restorationIntoAnotherScopeDoesNotLeakPriorAccountState() {
        var seed = LoginSeed("reconnect:school-a", InitialURL, InitialName, InitialUsername)
        val restorationTester = StateRestorationTester(composeRule)
        restorationTester.setContent {
            TestScreen(seed = seed)
        }
        replace(SCHOOL_LOGIN_URL_FIELD_TEST_TAG, EditedURL)
        replace(SCHOOL_LOGIN_SEARCH_FIELD_TEST_TAG, EditedName)
        replace(SCHOOL_LOGIN_USERNAME_FIELD_TEST_TAG, EditedUsername)
        input(SCHOOL_LOGIN_PASSWORD_FIELD_TEST_TAG, Password)

        composeRule.runOnIdle {
            seed = LoginSeed("reconnect:school-b", SecondURL, SecondName, SecondUsername)
        }
        restorationTester.emulateSavedInstanceStateRestore()

        assertText(SCHOOL_LOGIN_URL_FIELD_TEST_TAG, SecondURL)
        assertText(SCHOOL_LOGIN_SEARCH_FIELD_TEST_TAG, SecondName)
        assertText(SCHOOL_LOGIN_USERNAME_FIELD_TEST_TAG, SecondUsername)
        assertText(SCHOOL_LOGIN_PASSWORD_FIELD_TEST_TAG, "")
        composeRule.onNodeWithTag(SCHOOL_LOGIN_PASSWORD_VISIBILITY_TEST_TAG)
            .assertContentDescriptionEquals(context.getString(R.string.login_show_password))
    }

    @Test
    fun validCredentialsSubmitOneExactTuple() {
        val loginCount = AtomicInteger(0)
        val submittedCredentials = AtomicReference<Triple<String, String, String>>()
        composeRule.setContent {
            TestScreen(
                seed = LoginSeed("add-school", "", "", ""),
                onLogin = { school, username, password ->
                    loginCount.incrementAndGet()
                    submittedCredentials.set(Triple(school, username, password))
                },
            )
        }

        input(SCHOOL_LOGIN_URL_FIELD_TEST_TAG, EditedURL)
        input(SCHOOL_LOGIN_USERNAME_FIELD_TEST_TAG, EditedUsername)
        input(SCHOOL_LOGIN_PASSWORD_FIELD_TEST_TAG, Password)
        composeRule.onNodeWithTag(SCHOOL_LOGIN_CONNECT_BUTTON_TEST_TAG)
            .performScrollTo()
            .performClick()

        assertEquals(1, loginCount.get())
        assertEquals(Triple(EditedURL, EditedUsername, Password), submittedCredentials.get())
    }

    @Composable
    private fun TestScreen(
        seed: LoginSeed,
        onLogin: (String, String, String) -> Unit = { _, _, _ -> },
    ) {
        GradeyTheme {
            SchoolLoginScreen(
                isLoading = false,
                initialSchoolURL = seed.schoolURL,
                initialSchoolName = seed.schoolName,
                initialUsername = seed.username,
                stateScopeKey = seed.scope,
                onLoadDirectory = {},
                onRetryDirectory = {},
                onLogin = onLogin,
                onInputChanged = {},
                onOpenHelp = {},
                onOpenGitHub = {},
            )
        }
    }

    private fun input(tag: String, text: String) {
        composeRule.onNodeWithTag(tag)
            .performScrollTo()
            .performTextInput(text)
    }

    private fun replace(tag: String, text: String) {
        composeRule.onNodeWithTag(tag)
            .performScrollTo()
            .performTextReplacement(text)
    }

    private fun assertText(tag: String, expected: String) {
        composeRule.onNodeWithTag(tag)
            .performScrollTo()
            .assert(
                SemanticsMatcher.expectValue(
                    SemanticsProperties.EditableText,
                    AnnotatedString(expected),
                ),
            )
    }

    private data class LoginSeed(
        val scope: String,
        val schoolURL: String,
        val schoolName: String,
        val username: String,
    )

    private companion object {
        const val InitialURL = "https://initial.example.cz"
        const val InitialName = "Initial school"
        const val InitialUsername = "initial-student"
        const val EditedURL = "https://edited.example.cz"
        const val EditedName = "Edited school"
        const val EditedUsername = "edited-student"
        const val SecondURL = "https://second.example.cz"
        const val SecondName = "Second school"
        const val SecondUsername = "second-student"
        const val Password = "sensitive-password"
    }
}
