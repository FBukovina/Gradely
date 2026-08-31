package com.bukovinafilip.gradey.feature.auth

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgeAttestationInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun parentAgreementIsLabeledCheckboxWithMinimumTargetAndGatesConfirmation() {
        assertParentAgreementFlow(
            choiceText = context.getString(R.string.age_thirteen_to_fifteen),
            expectedKind = AgeAttestationKind.THIRTEEN_TO_FIFTEEN_WITH_PARENT,
        )
    }

    @Test
    fun underThirteenUsesTheSameGatedParentAgreementFlow() {
        assertParentAgreementFlow(
            choiceText = context.getString(R.string.age_under_thirteen),
            expectedKind = AgeAttestationKind.UNDER_THIRTEEN,
        )
    }

    private fun assertParentAgreementFlow(
        choiceText: String,
        expectedKind: AgeAttestationKind,
    ) {
        val confirmedKind = AtomicReference<AgeAttestationKind?>()
        composeRule.setContent {
            GradeyTheme {
                AgeAttestationScreen(
                    onConfirm = confirmedKind::set,
                    onOpenPrivacyPolicy = {},
                )
            }
        }

        composeRule.onNodeWithText(choiceText)
            .performScrollTo()
            .performClick()
        composeRule.runOnIdle { assertNull(confirmedKind.get()) }

        val agreement = composeRule.onNodeWithText(context.getString(R.string.age_parent_agreement))
            .performScrollTo()
            .assert(checkboxRoleMatcher)
            .assert(uncheckedMatcher)
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
        val continueButton = composeRule.onNodeWithText(context.getString(R.string.age_continue))
            .assertIsNotEnabled()

        agreement.performClick().assert(checkedMatcher)
        composeRule.runOnIdle { assertNull(confirmedKind.get()) }
        continueButton.performScrollTo().assertIsEnabled().performClick()

        composeRule.runOnIdle {
            assertEquals(expectedKind, confirmedKind.get())
        }
    }

    private companion object {
        val checkboxRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox)
        val uncheckedMatcher = SemanticsMatcher.expectValue(
            SemanticsProperties.ToggleableState,
            ToggleableState.Off,
        )
        val checkedMatcher = SemanticsMatcher.expectValue(
            SemanticsProperties.ToggleableState,
            ToggleableState.On,
        )
    }
}
