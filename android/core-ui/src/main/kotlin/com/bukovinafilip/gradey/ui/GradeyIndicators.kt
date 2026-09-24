package com.bukovinafilip.gradey.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.domain.AbsenceRiskLevel
import com.bukovinafilip.gradey.domain.GradeBand
import kotlin.math.max

enum class GradeyGradeBadgeSize {
    SMALL,
    REGULAR,
    LARGE,
}

data class GradeyGradeBadgeSpec(
    val fontSize: TextUnit,
    val minimumContentWidth: Dp,
    val horizontalPadding: Dp,
    val verticalPadding: Dp,
)

object GradeyGradeBadgeTokens {
    val CornerRadius = GradeyRadius.md
    const val MinimumTextScale = 0.6f

    fun spec(size: GradeyGradeBadgeSize): GradeyGradeBadgeSpec = when (size) {
        GradeyGradeBadgeSize.SMALL -> GradeyGradeBadgeSpec(
            fontSize = 17.sp,
            minimumContentWidth = 40.dp,
            horizontalPadding = GradeySpacing.sm,
            verticalPadding = GradeySpacing.sm,
        )
        GradeyGradeBadgeSize.REGULAR -> GradeyGradeBadgeSpec(
            fontSize = 20.sp,
            minimumContentWidth = 52.dp,
            horizontalPadding = GradeySpacing.md,
            verticalPadding = GradeySpacing.sm,
        )
        GradeyGradeBadgeSize.LARGE -> GradeyGradeBadgeSpec(
            fontSize = 34.sp,
            minimumContentWidth = 72.dp,
            horizontalPadding = GradeySpacing.lg,
            verticalPadding = GradeySpacing.md,
        )
    }
}

/** Tonal grade badge matching SwiftUI's shared `GradeBadge`. */
@Composable
fun GradeyGradeBadge(
    text: String,
    band: GradeBand,
    modifier: Modifier = Modifier,
    size: GradeyGradeBadgeSize = GradeyGradeBadgeSize.REGULAR,
) {
    val spec = GradeyGradeBadgeTokens.spec(size)
    val foreground = if (band == GradeBand.NEUTRAL) {
        MaterialTheme.colorScheme.onSurfaceVariant
    } else {
        band.color()
    }

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(GradeyGradeBadgeTokens.CornerRadius),
        color = band.softColor(),
        contentColor = foreground,
    ) {
        Box(
            modifier = Modifier
                .padding(
                    horizontal = spec.horizontalPadding,
                    vertical = spec.verticalPadding,
                )
                .widthIn(min = spec.minimumContentWidth),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = text,
                color = foreground,
                autoSize = TextAutoSize.StepBased(
                    minFontSize = spec.fontSize * GradeyGradeBadgeTokens.MinimumTextScale,
                    maxFontSize = spec.fontSize,
                ),
                style = TextStyle(
                    fontSize = spec.fontSize,
                    fontWeight = FontWeight.Bold,
                    fontFeatureSettings = "tnum",
                ),
                maxLines = 1,
                overflow = TextOverflow.Clip,
            )
        }
    }
}

object GradeyRiskIndicatorTokens {
    val RingSize = 38.dp
    val RingStrokeWidth = 4.5.dp
    const val RingRailOpacity = 0.22f

    val BarHeight = 6.dp
    val MinimumVisibleBarFill = 6.dp
    const val BarRailOpacity = 0.12f

    const val UnknownThresholdFillOpacity = 0.5f
}

/**
 * Progress relative to the school's threshold, falling back to a 0...100 scale
 * when no positive threshold is available.
 */
fun absenceRiskProgress(percentage: Double, threshold: Double?): Float {
    val safePercentage = when {
        percentage.isNaN() || percentage == Double.NEGATIVE_INFINITY -> return 0f
        percentage == Double.POSITIVE_INFINITY -> return 1f
        else -> percentage
    }
    val denominator = threshold?.takeIf { it.isFinite() && it > 0.0 } ?: 100.0
    return (safePercentage / denominator).coerceIn(0.0, 1.0).toFloat()
}

@Composable
fun AbsenceRiskLevel.riskColor(): Color = when (this) {
    AbsenceRiskLevel.SAFE -> MaterialTheme.colorScheme.primary
    AbsenceRiskLevel.WATCH -> GradeyColors.SystemOrange
    AbsenceRiskLevel.HIGH, AbsenceRiskLevel.OVER_LIMIT -> GradeyColors.Poor
    AbsenceRiskLevel.UNAVAILABLE -> MaterialTheme.colorScheme.onSurfaceVariant
}

/** Decorative circular absence-risk progress indicator. */
@Composable
fun GradeyAbsenceRiskRing(
    percentage: Double,
    threshold: Double?,
    level: AbsenceRiskLevel,
    modifier: Modifier = Modifier,
    size: Dp = GradeyRiskIndicatorTokens.RingSize,
    strokeWidth: Dp = GradeyRiskIndicatorTokens.RingStrokeWidth,
) {
    val progress = absenceRiskProgress(percentage, threshold)
    val fillColor = if (threshold == null) {
        MaterialTheme.colorScheme.onSurfaceVariant.copy(
            alpha = GradeyRiskIndicatorTokens.UnknownThresholdFillOpacity,
        )
    } else {
        level.riskColor()
    }
    val railColor = fillColor.copy(
        alpha = fillColor.alpha * GradeyRiskIndicatorTokens.RingRailOpacity,
    )

    Canvas(
        modifier = modifier
            .size(size)
            .clearAndSetSemantics { },
    ) {
        val strokeWidthPx = strokeWidth.toPx()
        val strokeInset = strokeWidthPx / 2f
        val arcSize = Size(
            width = this.size.width - strokeWidthPx,
            height = this.size.height - strokeWidthPx,
        )
        drawArc(
            color = railColor,
            startAngle = -90f,
            sweepAngle = 360f,
            useCenter = false,
            topLeft = Offset(strokeInset, strokeInset),
            size = arcSize,
            style = Stroke(width = strokeWidthPx, cap = StrokeCap.Round),
        )
        drawArc(
            color = fillColor,
            startAngle = -90f,
            sweepAngle = progress * 360f,
            useCenter = false,
            topLeft = Offset(strokeInset, strokeInset),
            size = arcSize,
            style = Stroke(width = strokeWidthPx, cap = StrokeCap.Round),
        )
    }
}

/** Decorative capsule absence-risk progress indicator. */
@Composable
fun GradeyRiskCapsuleBar(
    percentage: Double,
    threshold: Double?,
    level: AbsenceRiskLevel,
    modifier: Modifier = Modifier,
) {
    val progress = absenceRiskProgress(percentage, threshold)
    val fillColor = if (threshold == null) {
        MaterialTheme.colorScheme.onSurfaceVariant.copy(
            alpha = GradeyRiskIndicatorTokens.UnknownThresholdFillOpacity,
        )
    } else {
        level.riskColor()
    }
    val railColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(
        alpha = GradeyRiskIndicatorTokens.BarRailOpacity,
    )

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(GradeyRiskIndicatorTokens.BarHeight)
            .clearAndSetSemantics { },
    ) {
        val cornerRadius = CornerRadius(this.size.height / 2f)
        drawRoundRect(
            color = railColor,
            size = this.size,
            cornerRadius = cornerRadius,
        )
        if (progress > 0f) {
            val fillWidth = max(
                this.size.width * progress,
                minOf(GradeyRiskIndicatorTokens.MinimumVisibleBarFill.toPx(), this.size.width),
            )
            drawRoundRect(
                color = fillColor,
                size = Size(fillWidth, this.size.height),
                cornerRadius = cornerRadius,
            )
        }
    }
}
