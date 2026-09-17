package com.bukovinafilip.gradey.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.AppLanguage
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppLanguagePickerAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun languageRowsExposeGroupedRadioSelectionAndExactCzechCallback() {
        val latestSelection = AtomicReference<AppLanguage?>()
        setPicker(AppLanguage.ENGLISH, latestSelection::set)

        composeRule.onNodeWithTag(APP_LANGUAGE_OPTIONS_TEST_TAG)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.SelectableGroup))
        languageNode(R.string.language_system).assertIsNotSelected()
        languageNode(R.string.language_english).assertIsSelected()
        languageNode(R.string.language_czech)
            .assertIsNotSelected()
            .performClick()
            .assertIsSelected()
        languageNode(R.string.language_english).assertIsNotSelected()

        composeRule.runOnIdle { assertEquals(AppLanguage.CZECH, latestSelection.get()) }
    }

    @Test
    fun changingLanguagePreservesChronicallyOnlineVoice() {
        val latestSelection = AtomicReference<AppLanguage?>()
        setPicker(AppLanguage.ENGLISH_CHRONICALLY_ONLINE, latestSelection::set)

        languageNode(R.string.language_english).assertIsSelected()
        languageNode(R.string.language_czech).performClick().assertIsSelected()

        composeRule.runOnIdle {
            assertEquals(AppLanguage.CZECH_CHRONICALLY_ONLINE, latestSelection.get())
        }
    }

    @Test
    fun chronicallyOnlineUsesLabeledFullRowSwitchWithExactCallbacks() {
        val latestSelection = AtomicReference<AppLanguage?>()
        setPicker(AppLanguage.ENGLISH, latestSelection::set)

        val switch = composeRule.onNodeWithText(
            context.getString(R.string.language_chronically_online_title),
        )
            .assert(switchRoleMatcher)
            .assertTextContains(context.getString(R.string.language_chronically_online_subtitle))
            .assert(toggleOffMatcher)
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)

        switch.performClick().assert(toggleOnMatcher)
        composeRule.runOnIdle {
            assertEquals(AppLanguage.ENGLISH_CHRONICALLY_ONLINE, latestSelection.get())
        }

        switch.performClick().assert(toggleOffMatcher)
        composeRule.runOnIdle { assertEquals(AppLanguage.ENGLISH, latestSelection.get()) }
    }

    private fun setPicker(
        initialSelection: AppLanguage,
        onSelectionChange: (AppLanguage) -> Unit,
    ) {
        composeRule.setContent {
            var selection by remember { mutableStateOf(initialSelection) }
            GradeyTheme {
                AppLanguagePicker(
                    selection = selection,
                    onSelectionChange = {
                        selection = it
                        onSelectionChange(it)
                    },
                )
            }
        }
    }

    private fun languageNode(labelResource: Int): SemanticsNodeInteraction =
        composeRule.onNodeWithText(context.getString(labelResource))
            .assert(radioRoleMatcher)
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)

    private companion object {
        val radioRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton)
        val switchRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch)
        val toggleOffMatcher = SemanticsMatcher.expectValue(
            SemanticsProperties.ToggleableState,
            ToggleableState.Off,
        )
        val toggleOnMatcher = SemanticsMatcher.expectValue(
            SemanticsProperties.ToggleableState,
            ToggleableState.On,
        )
    }
}
