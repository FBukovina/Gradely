package com.bukovinafilip.gradey.feature.stravacz

import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
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
class StravaCZCredentialRestorationTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun restorationPreservesNonSecretFieldsButClearsAndHidesPassword() {
        val connectCount = AtomicInteger(0)
        val connectedCredentials = AtomicReference<Triple<String, String, String>>()
        val restorationTester = StateRestorationTester(composeRule)
        restorationTester.setContent {
            TestScreen { canteenNumber, username, password ->
                connectCount.incrementAndGet()
                connectedCredentials.set(Triple(canteenNumber, username, password))
            }
        }

        enterCredentials()
        composeRule.onNodeWithTag(STRAVACZ_PASSWORD_VISIBILITY_TEST_TAG)
            .performClick()
            .assertContentDescriptionEquals(context.getString(R.string.stravacz_hide_password))
        composeRule.onNodeWithTag(STRAVACZ_CONNECT_BUTTON_TEST_TAG).assertIsEnabled()

        restorationTester.emulateSavedInstanceStateRestore()

        composeRule.onNodeWithTag(STRAVACZ_CANTEEN_FIELD_TEST_TAG)
            .assertEditableTextEquals(CanteenNumber)
        composeRule.onNodeWithTag(STRAVACZ_USERNAME_FIELD_TEST_TAG)
            .assertEditableTextEquals(Username)
        composeRule.onNodeWithTag(STRAVACZ_PASSWORD_FIELD_TEST_TAG)
            .assertEditableTextEquals("")
        composeRule.onNodeWithTag(STRAVACZ_PASSWORD_VISIBILITY_TEST_TAG)
            .assertContentDescriptionEquals(context.getString(R.string.stravacz_show_password))
        composeRule.onNodeWithTag(STRAVACZ_CONNECT_BUTTON_TEST_TAG).assertIsNotEnabled()
        assertEquals(0, connectCount.get())
        assertNull(connectedCredentials.get())
    }

    @Test
    fun validCredentialsInvokeConnectOnceWithExactTuple() {
        val connectCount = AtomicInteger(0)
        val connectedCredentials = AtomicReference<Triple<String, String, String>>()
        composeRule.setContent {
            TestScreen { canteenNumber, username, password ->
                connectCount.incrementAndGet()
                connectedCredentials.set(Triple(canteenNumber, username, password))
            }
        }

        enterCredentials()
        composeRule.onNodeWithTag(STRAVACZ_CONNECT_BUTTON_TEST_TAG)
            .performScrollTo()
            .assertIsEnabled()
            .performClick()

        assertEquals(1, connectCount.get())
        assertEquals(Triple(CanteenNumber, Username, Password), connectedCredentials.get())
    }

    @Composable
    private fun TestScreen(onConnect: (String, String, String) -> Unit) {
        GradeyTheme {
            StravaCZScreen(
                session = null,
                menu = null,
                isLoading = false,
                isRefreshing = false,
                submittingMealID = null,
                errorMessage = null,
                onConnect = onConnect,
                onRefresh = {},
                onSetMeal = { _, _ -> },
                onDisconnect = {},
                onOpenAccount = {},
                onOpenGradeyTools = {},
            )
        }
    }

    private fun enterCredentials() {
        composeRule.onNodeWithTag(STRAVACZ_CANTEEN_FIELD_TEST_TAG)
            .performScrollTo()
            .performTextInput(CanteenNumber)
        composeRule.onNodeWithTag(STRAVACZ_USERNAME_FIELD_TEST_TAG)
            .performScrollTo()
            .performTextInput(Username)
        composeRule.onNodeWithTag(STRAVACZ_PASSWORD_FIELD_TEST_TAG)
            .performScrollTo()
            .performTextInput(Password)
    }

    private companion object {
        const val CanteenNumber = "1234"
        const val Username = "student"
        const val Password = "sensitive-password"
    }
}

private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertEditableTextEquals(
    expected: String,
) = assert(
    SemanticsMatcher.expectValue(
        SemanticsProperties.EditableText,
        AnnotatedString(expected),
    ),
)
