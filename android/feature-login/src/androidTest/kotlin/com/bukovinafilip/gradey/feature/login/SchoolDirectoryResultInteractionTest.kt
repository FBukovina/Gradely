package com.bukovinafilip.gradey.feature.login

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.bukovinafilip.gradey.ui.GradeyTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SchoolDirectoryResultInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun resultIsAnAccessibleButtonAndSelectsTheExactSchool() {
        composeRule.setContent {
            GradeyTheme {
                SchoolLoginScreen(
                    isLoading = false,
                    directorySchools = listOf(OtherSchool, School),
                    onLoadDirectory = {},
                    onRetryDirectory = {},
                    onLogin = { _, _, _ -> },
                    onInputChanged = {},
                    onOpenHelp = {},
                    onOpenGitHub = {},
                )
            }
        }

        composeRule.onNodeWithTag(SCHOOL_LOGIN_SEARCH_FIELD_TEST_TAG)
            .performTextInput("gymnazium")

        composeRule.onNodeWithTag("$SCHOOL_LOGIN_RESULT_TEST_TAG_PREFIX${School.id}")
            .assert(buttonRoleMatcher)
            .assertTextContains(School.trimmedName)
            .assertTextContains("${School.trimmedTown} · ${School.trimmedSchoolURL}")
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
            .performClick()

        assertEditableText(SCHOOL_LOGIN_SEARCH_FIELD_TEST_TAG, School.trimmedName)
        assertEditableText(SCHOOL_LOGIN_URL_FIELD_TEST_TAG, School.trimmedSchoolURL)
        composeRule.onNodeWithTag("$SCHOOL_LOGIN_RESULT_TEST_TAG_PREFIX${School.id}")
            .assertDoesNotExist()
    }

    private fun assertEditableText(tag: String, expected: String) {
        composeRule.onNodeWithTag(tag)
            .performScrollTo()
            .assert(
                SemanticsMatcher.expectValue(
                    SemanticsProperties.EditableText,
                    AnnotatedString(expected),
                ),
            )
    }

    private companion object {
        val buttonRoleMatcher = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)

        val School = SchoolDirectorySchool(
            id = "omska",
            name = "  Gymnázium Praha 10, Omská  ",
            town = " Praha ",
            schoolURL = " https://bakalari.omska.cz ",
        )

        val OtherSchool = SchoolDirectorySchool(
            id = "other-omska",
            name = "Gymnázium Praha 10, Omská",
            town = "Brno",
            schoolURL = "https://other.example.cz",
        )
    }
}
