package com.bukovinafilip.gradey.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.junit.Assert.assertEquals
import org.junit.Test

class GradeyIndicatorTokensTest {
    @Test
    fun gradeBadgeSpecsMatchIosSharedComponent() {
        assertEquals(16.dp, GradeyGradeBadgeTokens.CornerRadius)
        assertEquals(0.6f, GradeyGradeBadgeTokens.MinimumTextScale)
        assertEquals(
            GradeyGradeBadgeSpec(
                fontSize = 17.sp,
                minimumContentWidth = 40.dp,
                horizontalPadding = 8.dp,
                verticalPadding = 8.dp,
            ),
            GradeyGradeBadgeTokens.spec(GradeyGradeBadgeSize.SMALL),
        )
        assertEquals(
            GradeyGradeBadgeSpec(
                fontSize = 20.sp,
                minimumContentWidth = 52.dp,
                horizontalPadding = 12.dp,
                verticalPadding = 8.dp,
            ),
            GradeyGradeBadgeTokens.spec(GradeyGradeBadgeSize.REGULAR),
        )
        assertEquals(
            GradeyGradeBadgeSpec(
                fontSize = 34.sp,
                minimumContentWidth = 72.dp,
                horizontalPadding = 16.dp,
                verticalPadding = 12.dp,
            ),
            GradeyGradeBadgeTokens.spec(GradeyGradeBadgeSize.LARGE),
        )
    }

    @Test
    fun riskIndicatorSpecsMatchIosComponents() {
        assertEquals(38.dp, GradeyRiskIndicatorTokens.RingSize)
        assertEquals(4.5.dp, GradeyRiskIndicatorTokens.RingStrokeWidth)
        assertEquals(0.22f, GradeyRiskIndicatorTokens.RingRailOpacity)
        assertEquals(6.dp, GradeyRiskIndicatorTokens.BarHeight)
        assertEquals(6.dp, GradeyRiskIndicatorTokens.MinimumVisibleBarFill)
        assertEquals(0.12f, GradeyRiskIndicatorTokens.BarRailOpacity)
        assertEquals(0.5f, GradeyRiskIndicatorTokens.UnknownThresholdFillOpacity)
        assertEquals(Color(0xFFFF9500), GradeyColors.SystemOrange)
    }

    @Test
    fun riskProgressUsesThresholdOrHundredPercentFallbackAndClamps() {
        assertEquals(0.5f, absenceRiskProgress(10.0, 20.0), 0f)
        assertEquals(0.25f, absenceRiskProgress(25.0, null), 0f)
        assertEquals(0.25f, absenceRiskProgress(25.0, 0.0), 0f)
        assertEquals(0f, absenceRiskProgress(-5.0, 20.0), 0f)
        assertEquals(1f, absenceRiskProgress(30.0, 20.0), 0f)
        assertEquals(1f, absenceRiskProgress(150.0, null), 0f)
        assertEquals(0.25f, absenceRiskProgress(25.0, Double.NaN), 0f)
        assertEquals(0.25f, absenceRiskProgress(25.0, Double.POSITIVE_INFINITY), 0f)
        assertEquals(0f, absenceRiskProgress(Double.NaN, 20.0), 0f)
        assertEquals(0f, absenceRiskProgress(Double.NEGATIVE_INFINITY, 20.0), 0f)
        assertEquals(1f, absenceRiskProgress(Double.POSITIVE_INFINITY, 20.0), 0f)
    }
}
