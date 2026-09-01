package com.bukovinafilip.gradey.ui

import androidx.compose.ui.graphics.Color
import com.bukovinafilip.gradey.domain.GradeBand
import org.junit.Assert.assertEquals
import org.junit.Test

class GradeyThemeTokensTest {
    @Test
    fun brandAndLessonSemanticColorsMatchIosTokens() {
        assertEquals(Color(0xFF041814), GradeyColors.OnAccent)
        assertEquals(Color(0xFFD83E4F), GradeyColors.Poor)
        assertEquals(Color(0xFFD98F10), GradeyColors.Average)
        assertEquals(Color(0xFF108A94), GradeyColors.Good)
        assertEquals(Color(0xFFAF52DE), GradeyColors.SystemPurple)
    }

    @Test
    fun gradeBandsExposeIosForegroundAndSoftFillTokens() {
        val expected = mapOf(
            GradeBand.EXCELLENT to Color(0xFF1E9F69),
            GradeBand.GOOD to Color(0xFF108A94),
            GradeBand.AVERAGE to Color(0xFFD98F10),
            GradeBand.POOR to Color(0xFFD83E4F),
        )

        expected.forEach { (band, color) ->
            assertEquals(color, band.color())
            assertEquals(color.copy(alpha = 0.14f), band.softColor())
        }
        assertEquals(Color.Gray, GradeBand.NEUTRAL.color())
        assertEquals(Color.Gray.copy(alpha = 0.16f), GradeBand.NEUTRAL.softColor())
    }
}
