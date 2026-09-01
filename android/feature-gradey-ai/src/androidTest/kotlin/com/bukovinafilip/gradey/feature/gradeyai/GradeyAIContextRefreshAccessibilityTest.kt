package com.bukovinafilip.gradey.feature.gradeyai

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GradeyAIContextRefreshAccessibilityTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun refreshKeepsOneStableButtonLabelWhileBusyAndSuppressesAnotherClick() {
        val refreshes = AtomicInteger(0)
        composeRule.setContent {
            var isRefreshing by remember { mutableStateOf(false) }
            GradeyTheme {
                GradeyAIContextRefreshButton(
                    isRefreshing = isRefreshing,
                    isSending = false,
                    onRefresh = {
                        refreshes.incrementAndGet()
                        isRefreshing = true
                    },
                    modifier = Modifier.testTag(REFRESH_TEST_TAG),
                )
            }
        }

        refreshNode()
            .assert(buttonRoleMatcher)
            .assertContentDescriptionEquals(refreshDescription)
            .assertHasClickAction()
            .assertIsEnabled()
            .assertHeightIsAtLeast(48.dp)
            .assertWidthIsAtLeast(48.dp)
            .performClick()

        refreshNode()
            .assert(buttonRoleMatcher)
            .assertContentDescriptionEquals(refreshDescription)
            .assertHasClickAction()
            .assertIsNotEnabled()
            .performClick()
        composeRule.runOnIdle { assertEquals(1, refreshes.get()) }
    }

    private val refreshDescription
        get() = context.getString(R.string.gradey_ai_context_refresh)

    private fun refreshNode() = composeRule.onNodeWithTag(REFRESH_TEST_TAG, useUnmergedTree = true)

    private companion object {
        const val REFRESH_TEST_TAG = "gradeyAIContextRefresh"
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
    }
}
