package com.bukovinafilip.gradey.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

class GradeySurfaceTokensTest {
    @Test
    fun standardAuroraMatchesIosThreeGlowGeometry() {
        val glows = GradeyAuroraTokens.glows(GradeyAuroraStyle.STANDARD, darkTheme = false)

        assertEquals(3, glows.size)
        assertEquals(
            listOf(
                GradeyAuroraGlowSpec(GradeyAuroraColorRole.PRIMARY, 0.30f, 1.60f, 0.52f, 0.02f, 55.dp),
                GradeyAuroraGlowSpec(GradeyAuroraColorRole.SECONDARY, 0.22f, 1.15f, 1.05f, 0.26f, 55.dp),
                GradeyAuroraGlowSpec(GradeyAuroraColorRole.PRIMARY, 0.16f, 1.05f, -0.08f, 0.62f, 55.dp),
            ),
            glows,
        )
        assertEquals(glows, GradeyAuroraTokens.glows(GradeyAuroraStyle.STANDARD, darkTheme = true))
    }

    @Test
    fun accountAuroraKeepsIosGeometryAndAdaptsOpacity() {
        val light = GradeyAuroraTokens.accountSettings(darkTheme = false)
        val dark = GradeyAuroraTokens.accountSettings(darkTheme = true)

        assertEquals(3, light.size)
        assertEquals(listOf(0.10f, 0.07f, 0.05f), light.map { it.opacity })
        assertEquals(listOf(0.15f, 0.09f, 0.06f), dark.map { it.opacity })
        assertEquals(listOf(0.92f, 0.72f, 0.78f), light.map { it.sizeWidthFraction })
        assertEquals(listOf(0.68f, 0.12f, 0.98f), light.map { it.centerXWidthFraction })
        assertEquals(listOf(0.08f, 0.28f, 0.52f), light.map { it.centerYHeightFraction })
        assertEquals(listOf(42.dp, 38.dp, 44.dp), light.map { it.blurRadius })
    }

    @Test
    fun primaryActionMatchesIosSharedButtonSpec() {
        assertEquals(14.dp, GradeyPrimaryActionTokens.VerticalPadding)
        assertEquals(16.dp, GradeyPrimaryActionTokens.CornerRadius)
        assertEquals(16.dp, GradeyPrimaryActionTokens.ShadowRadius)
        assertEquals(8.dp, GradeyPrimaryActionTokens.ShadowYOffset)
        assertEquals(0.45f, GradeyPrimaryActionTokens.ShadowOpacity)
        assertEquals(0.85f, GradeyPrimaryActionTokens.PressedOpacity)
        assertEquals(0.45f, GradeyPrimaryActionTokens.DisabledOpacity)
        assertEquals(0.25f, GradeyPrimaryActionTokens.DisabledSaturation)
        assertEquals(0.98f, GradeyPrimaryActionTokens.PressedScale)
        assertEquals(150, GradeyPrimaryActionTokens.AnimationDurationMillis)
    }

    @Test
    fun groupedCardTokensAndTertiarySurfacesMatchIosSemantics() {
        assertEquals(16.dp, GradeyCardTokens.ContentPadding)
        assertEquals(20.dp, GradeyCardTokens.CornerRadius)
        assertEquals(1.dp, GradeyCardTokens.OutlineWidth)
        assertEquals(0.06f, GradeyCardTokens.OutlineOpacity)
        assertEquals(12.dp, GradeyCardTokens.ShadowBlurRadius)
        assertEquals(6.dp, GradeyCardTokens.ShadowYOffset)
        assertEquals(0.06f, GradeyCardTokens.ShadowOpacity)
        assertEquals(Color(0xFFF2F2F7), GradeyColors.LightTertiaryGroupedSurface)
        assertEquals(Color(0xFF2C2C2E), GradeyColors.DarkTertiaryGroupedSurface)
    }
}
