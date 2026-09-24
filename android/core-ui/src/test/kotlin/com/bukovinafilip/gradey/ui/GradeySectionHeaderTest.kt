package com.bukovinafilip.gradey.ui

import androidx.compose.ui.unit.sp
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class GradeySectionHeaderTest {
    @Test
    fun tokensMatchTheIosSectionHeader() {
        assertEquals(13.sp, GradeySectionHeaderTokens.FontSize)
        assertEquals(18.sp, GradeySectionHeaderTokens.LineHeight)
        assertEquals(0.6.sp, GradeySectionHeaderTokens.LetterSpacing)
    }

    @Test
    fun czechTextUsesLocaleAwareUppercase() {
        assertEquals(
            "PŘÍŠTÍ ZNÁMKY A TRENDY",
            gradeySectionHeaderText(
                text = "příští známky a trendy",
                locale = Locale.forLanguageTag("cs-CZ"),
            ),
        )
    }

    @Test
    fun englishTextUsesLocaleAwareUppercase() {
        assertEquals(
            "NEW MARKS AND TRENDS",
            gradeySectionHeaderText(
                text = "new marks and trends",
                locale = Locale.ENGLISH,
            ),
        )
    }

    @Test
    fun localeAwareUppercaseDoesNotFallBackToEnglishRules() {
        assertEquals(
            "RİSK",
            gradeySectionHeaderText(
                text = "risk",
                locale = Locale.forLanguageTag("tr-TR"),
            ),
        )
    }
}
