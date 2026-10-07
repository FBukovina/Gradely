package com.bukovinafilip.gradey.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GradeySectionHeaderInstrumentedTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun labelIsUppercaseAndExposesHeadingSemantics() {
        composeRule.setContent {
            GradeyTheme {
                GradeySectionHeader(text = "header label")
            }
        }

        composeRule.onNodeWithText("HEADER LABEL")
            .assertIsDisplayed()
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
    }

    @Test
    fun weightedHeaderLeavesRoomForATrailingRowAction() {
        composeRule.setContent {
            GradeyTheme {
                Row(modifier = Modifier.width(240.dp)) {
                    GradeySectionHeader(
                        text = "section title",
                        modifier = Modifier
                            .weight(1f)
                            .testTag(HeaderTag),
                    )
                    Text(
                        text = "ACTION",
                        modifier = Modifier.testTag(ActionTag),
                    )
                }
            }
        }

        val headerBounds = composeRule.onNodeWithTag(HeaderTag)
            .assertIsDisplayed()
            .fetchSemanticsNode()
            .boundsInRoot
        val actionBounds = composeRule.onNodeWithTag(ActionTag)
            .assertIsDisplayed()
            .fetchSemanticsNode()
            .boundsInRoot

        assertTrue(
            "The full-width header must not overlap its trailing row action",
            headerBounds.right <= actionBounds.left,
        )
    }

    @Test
    fun standaloneHeaderFillsItsParentWidth() {
        composeRule.setContent {
            GradeyTheme {
                Box(
                    modifier = Modifier
                        .width(240.dp)
                        .testTag(ParentTag),
                ) {
                    GradeySectionHeader(
                        text = "section title",
                        modifier = Modifier.testTag(HeaderTag),
                    )
                }
            }
        }

        val parentBounds = composeRule.onNodeWithTag(ParentTag)
            .assertIsDisplayed()
            .fetchSemanticsNode()
            .boundsInRoot
        val headerBounds = composeRule.onNodeWithTag(HeaderTag)
            .assertIsDisplayed()
            .fetchSemanticsNode()
            .boundsInRoot

        assertTrue(
            "A standalone section header must fill its parent's width",
            parentBounds.left == headerBounds.left && parentBounds.right == headerBounds.right,
        )
    }

    private companion object {
        const val HeaderTag = "gradey-section-header"
        const val ActionTag = "gradey-section-header-action"
        const val ParentTag = "gradey-section-header-parent"
    }
}
