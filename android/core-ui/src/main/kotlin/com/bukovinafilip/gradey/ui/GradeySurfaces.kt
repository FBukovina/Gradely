package com.bukovinafilip.gradey.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** The two app-wide aurora layouts defined by the SwiftUI design system. */
enum class GradeyAuroraStyle {
    STANDARD,
    ACCOUNT_SETTINGS,
}

enum class GradeyAuroraColorRole {
    PRIMARY,
    SECONDARY,
}

/**
 * Platform-neutral geometry for one aurora glow.
 *
 * Size and position are fractions of the available width/height so the same
 * composition scales from phones to expanded-width layouts.
 */
data class GradeyAuroraGlowSpec(
    val colorRole: GradeyAuroraColorRole,
    val opacity: Float,
    val sizeWidthFraction: Float,
    val centerXWidthFraction: Float,
    val centerYHeightFraction: Float,
    val blurRadius: Dp,
)

object GradeyAuroraTokens {
    val Standard = listOf(
        GradeyAuroraGlowSpec(
            colorRole = GradeyAuroraColorRole.PRIMARY,
            opacity = 0.30f,
            sizeWidthFraction = 1.60f,
            centerXWidthFraction = 0.52f,
            centerYHeightFraction = 0.02f,
            blurRadius = 55.dp,
        ),
        GradeyAuroraGlowSpec(
            colorRole = GradeyAuroraColorRole.SECONDARY,
            opacity = 0.22f,
            sizeWidthFraction = 1.15f,
            centerXWidthFraction = 1.05f,
            centerYHeightFraction = 0.26f,
            blurRadius = 55.dp,
        ),
        GradeyAuroraGlowSpec(
            colorRole = GradeyAuroraColorRole.PRIMARY,
            opacity = 0.16f,
            sizeWidthFraction = 1.05f,
            centerXWidthFraction = -0.08f,
            centerYHeightFraction = 0.62f,
            blurRadius = 55.dp,
        ),
    )

    fun accountSettings(darkTheme: Boolean) = listOf(
        GradeyAuroraGlowSpec(
            colorRole = GradeyAuroraColorRole.PRIMARY,
            opacity = if (darkTheme) 0.15f else 0.10f,
            sizeWidthFraction = 0.92f,
            centerXWidthFraction = 0.68f,
            centerYHeightFraction = 0.08f,
            blurRadius = 42.dp,
        ),
        GradeyAuroraGlowSpec(
            colorRole = GradeyAuroraColorRole.SECONDARY,
            opacity = if (darkTheme) 0.09f else 0.07f,
            sizeWidthFraction = 0.72f,
            centerXWidthFraction = 0.12f,
            centerYHeightFraction = 0.28f,
            blurRadius = 38.dp,
        ),
        GradeyAuroraGlowSpec(
            colorRole = GradeyAuroraColorRole.PRIMARY,
            opacity = if (darkTheme) 0.06f else 0.05f,
            sizeWidthFraction = 0.78f,
            centerXWidthFraction = 0.98f,
            centerYHeightFraction = 0.52f,
            blurRadius = 44.dp,
        ),
    )

    fun glows(style: GradeyAuroraStyle, darkTheme: Boolean): List<GradeyAuroraGlowSpec> = when (style) {
        GradeyAuroraStyle.STANDARD -> Standard
        GradeyAuroraStyle.ACCOUNT_SETTINGS -> accountSettings(darkTheme)
    }
}

/**
 * Reusable app-wide grouped background with the SwiftUI three-glow aurora.
 * Place it first in a full-size [androidx.compose.foundation.layout.Box].
 */
@Composable
fun GradeyAuroraBackground(
    modifier: Modifier = Modifier,
    style: GradeyAuroraStyle = GradeyAuroraStyle.STANDARD,
) {
    val colorScheme = MaterialTheme.colorScheme
    val darkTheme = colorScheme.background == GradeyColors.DarkGroupedBackground
    val glows = GradeyAuroraTokens.glows(style, darkTheme)

    Canvas(
        modifier = modifier
            .fillMaxSize()
            .background(colorScheme.background),
    ) {
        glows.forEach { glow ->
            val center = Offset(
                x = size.width * glow.centerXWidthFraction,
                y = size.height * glow.centerYHeightFraction,
            )
            // SwiftUI blurs the already feathered radial circle. Extending the
            // gradient by that blur radius gives the same soft falloff without
            // relying on Android-12-only render effects.
            val radius = (size.width * glow.sizeWidthFraction / 2f) + glow.blurRadius.toPx()
            val baseColor = when (glow.colorRole) {
                GradeyAuroraColorRole.PRIMARY -> colorScheme.primary
                GradeyAuroraColorRole.SECONDARY -> colorScheme.secondary
            }
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(baseColor.copy(alpha = glow.opacity), Color.Transparent),
                    center = center,
                    radius = radius,
                ),
                center = center,
                radius = radius,
            )
        }
    }
}

object GradeyPrimaryActionTokens {
    val VerticalPadding = 14.dp
    val HorizontalPadding = 24.dp
    val CornerRadius = GradeyRadius.md
    val ShadowRadius = 16.dp
    val ShadowYOffset = 8.dp
    const val ShadowOpacity = 0.45f
    const val PressedOpacity = 0.85f
    const val DisabledOpacity = 0.45f
    const val DisabledSaturation = 0.25f
    const val PressedScale = 0.98f
    const val AnimationDurationMillis = 150
}

/** The app-wide top-leading to bottom-trailing brand gradient. */
@Composable
fun gradeyBrandGradient(): Brush = Brush.linearGradient(
    colors = listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.secondary),
)

/** Full-width primary CTA matching SwiftUI's shared `PrimaryButtonStyle`. */
@Composable
fun GradeyPrimaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val targetScale = if (enabled && pressed) GradeyPrimaryActionTokens.PressedScale else 1f
    val targetAlpha = when {
        !enabled -> GradeyPrimaryActionTokens.DisabledOpacity
        pressed -> GradeyPrimaryActionTokens.PressedOpacity
        else -> 1f
    }
    val scale by animateFloatAsState(
        targetValue = targetScale,
        animationSpec = tween(GradeyPrimaryActionTokens.AnimationDurationMillis),
        label = "Gradey primary button scale",
    )
    val alpha by animateFloatAsState(
        targetValue = targetAlpha,
        animationSpec = tween(GradeyPrimaryActionTokens.AnimationDurationMillis),
        label = "Gradey primary button alpha",
    )
    val saturation by animateFloatAsState(
        targetValue = if (enabled) 1f else GradeyPrimaryActionTokens.DisabledSaturation,
        animationSpec = tween(GradeyPrimaryActionTokens.AnimationDurationMillis),
        label = "Gradey primary button saturation",
    )
    val shape = RoundedCornerShape(GradeyPrimaryActionTokens.CornerRadius)
    val shadowColor = MaterialTheme.colorScheme.primary.copy(
        alpha = if (enabled) GradeyPrimaryActionTokens.ShadowOpacity else 0f,
    )

    Button(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                this.alpha = alpha
                colorFilter = if (saturation < 1f) {
                    ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(saturation) })
                } else {
                    null
                }
            }
            .shadow(
                elevation = if (enabled) GradeyPrimaryActionTokens.ShadowRadius else 0.dp,
                shape = shape,
                clip = false,
                ambientColor = shadowColor,
                spotColor = shadowColor,
            )
            .background(gradeyBrandGradient(), shape),
        enabled = enabled,
        shape = shape,
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.Transparent,
            contentColor = MaterialTheme.colorScheme.onPrimary,
            disabledContainerColor = Color.Transparent,
            disabledContentColor = MaterialTheme.colorScheme.onPrimary,
        ),
        contentPadding = PaddingValues(
            horizontal = GradeyPrimaryActionTokens.HorizontalPadding,
            vertical = GradeyPrimaryActionTokens.VerticalPadding,
        ),
        interactionSource = interactionSource,
        content = content,
    )
}

enum class GradeyGroupedSurfaceLevel {
    SECONDARY,
    TERTIARY,
}

object GradeyCardTokens {
    val ContentPadding = GradeySpacing.lg
    val CornerRadius = GradeyRadius.card
    val OutlineWidth = 1.dp
    const val OutlineOpacity = 0.06f
    val ShadowBlurRadius = 12.dp
    val ShadowYOffset = 6.dp
    const val ShadowOpacity = 0.06f

    // Compose elevation has no independent blur/y-offset controls. Six dp is
    // the closest platform-native expression of SwiftUI's y=6 soft shadow.
    val ComposeElevation = 6.dp
}

@Composable
internal fun GradeyGroupedSurfaceLevel.containerColor(): Color = when (this) {
    GradeyGroupedSurfaceLevel.SECONDARY -> MaterialTheme.colorScheme.surfaceContainer
    GradeyGroupedSurfaceLevel.TERTIARY -> MaterialTheme.colorScheme.surfaceContainerHigh
}
