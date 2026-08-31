package com.bukovinafilip.gradey.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.domain.GradeBand

object GradeyColors {
    val Primary = Color(0xFF17A185)
    val Secondary = Color(0xFF1DA565)
    val OnAccent = Color(0xFF041814)
    val Excellent = Color(0xFF1E9F69)
    val Good = Color(0xFF108A94)
    val Average = Color(0xFFD98F10)
    val Poor = Color(0xFFD83E4F)
    val SystemPurple = Color(0xFFAF52DE)
    val LightGroupedBackground = Color(0xFFF2F2F7)
    val LightGroupedSurface = Color(0xFFFFFFFF)
    val LightTertiaryGroupedSurface = Color(0xFFF2F2F7)
    val DarkGroupedBackground = Color(0xFF080B0A)
    val DarkGroupedSurface = Color(0xFF171C1B)
    val DarkTertiaryGroupedSurface = Color(0xFF2C2C2E)

    val AuroraGlows = listOf(
        Primary.copy(alpha = 0.30f),
        Secondary.copy(alpha = 0.22f),
        Primary.copy(alpha = 0.16f),
    )
}

object GradeySpacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 24.dp
    val xxl = 32.dp
}

object GradeyRadius {
    val sm = 12.dp
    val md = 16.dp
    val card = 20.dp
    val xl = 28.dp
}

private val LightScheme = lightColorScheme(
    primary = GradeyColors.Primary,
    secondary = GradeyColors.Secondary,
    tertiary = GradeyColors.Good,
    background = GradeyColors.LightGroupedBackground,
    surface = GradeyColors.LightGroupedSurface,
    surfaceContainer = GradeyColors.LightGroupedSurface,
    surfaceContainerHigh = GradeyColors.LightTertiaryGroupedSurface,
    surfaceContainerLow = Color(0xFFF8FAF9),
    surfaceVariant = Color(0xFFE8EEEC),
    onPrimary = GradeyColors.OnAccent,
    onSecondary = GradeyColors.OnAccent,
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFF1AFFBE),
    secondary = Color(0xFF1FF98C),
    tertiary = Color(0xFF5AD7E0),
    background = GradeyColors.DarkGroupedBackground,
    surface = GradeyColors.DarkGroupedSurface,
    surfaceContainer = GradeyColors.DarkGroupedSurface,
    surfaceContainerHigh = GradeyColors.DarkTertiaryGroupedSurface,
    surfaceContainerLow = Color(0xFF111615),
    surfaceVariant = Color(0xFF28312F),
    onPrimary = GradeyColors.OnAccent,
    onSecondary = GradeyColors.OnAccent,
)

private val SpaceGrotesk = FontFamily(
    Font(R.font.space_grotesk_bold, weight = FontWeight.Bold),
)

private val GradeyTypography = Typography(
    displayLarge = Typography().displayLarge.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold),
    displayMedium = Typography().displayMedium.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold),
    displaySmall = Typography().displaySmall.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold),
    headlineLarge = Typography().headlineLarge.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold),
    headlineMedium = Typography().headlineMedium.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold),
    headlineSmall = Typography().headlineSmall.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold),
    titleLarge = Typography().titleLarge.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold),
)

private val GradeyShapes = Shapes(
    extraSmall = RoundedCornerShape(GradeyRadius.sm),
    small = RoundedCornerShape(GradeyRadius.sm),
    medium = RoundedCornerShape(GradeyRadius.md),
    large = RoundedCornerShape(GradeyRadius.card),
    extraLarge = RoundedCornerShape(GradeyRadius.xl),
)

@Composable
fun GradeyTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkScheme else LightScheme,
        typography = GradeyTypography,
        shapes = GradeyShapes,
        content = content,
    )
}

@Composable
fun GradeyScreen(
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(GradeySpacing.lg),
    content: @Composable () -> Unit,
) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.background,
    ) {
        Column(
            modifier = Modifier.padding(contentPadding),
            verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg),
        ) {
            content()
        }
    }
}

@Composable
fun GradeyHero(
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GradeyRadius.card))
            .background(gradeyBrandGradient())
            .padding(GradeySpacing.xl),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
            Text(
                title,
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.headlineMedium,
                color = GradeyColors.OnAccent,
                fontWeight = FontWeight.Bold,
            )
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = GradeyColors.OnAccent.copy(alpha = 0.84f))
        }
    }
}

@Composable
fun GradeySectionCard(
    modifier: Modifier = Modifier,
    title: String? = null,
    content: @Composable () -> Unit,
) = GradeySectionCard(
    modifier = modifier,
    title = title,
    surfaceLevel = GradeyGroupedSurfaceLevel.SECONDARY,
    content = content,
)

@Composable
fun GradeySectionCard(
    modifier: Modifier = Modifier,
    title: String? = null,
    surfaceLevel: GradeyGroupedSurfaceLevel,
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(GradeyCardTokens.CornerRadius)
    Card(
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                elevation = GradeyCardTokens.ComposeElevation,
                shape = shape,
                clip = false,
                ambientColor = Color.Black.copy(alpha = GradeyCardTokens.ShadowOpacity),
                spotColor = Color.Black.copy(alpha = GradeyCardTokens.ShadowOpacity),
            ),
        shape = shape,
        colors = CardDefaults.cardColors(containerColor = surfaceLevel.containerColor()),
        border = BorderStroke(
            GradeyCardTokens.OutlineWidth,
            MaterialTheme.colorScheme.onSurface.copy(alpha = GradeyCardTokens.OutlineOpacity),
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier.padding(GradeyCardTokens.ContentPadding),
            verticalArrangement = Arrangement.spacedBy(GradeySpacing.md),
        ) {
            if (title != null) {
                Text(
                    title,
                    modifier = Modifier.semantics { heading() },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(GradeySpacing.xs))
            }
            content()
        }
    }
}

@Composable
fun StatusChip(
    text: String,
    color: Color = MaterialTheme.colorScheme.onSurfaceVariant,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = CircleShape,
        color = color.copy(alpha = 0.14f),
        contentColor = color,
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
            color = color,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
fun MetadataRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = FontWeight.SemiBold)
    }
}

fun GradeBand.color(): Color = when (this) {
    GradeBand.EXCELLENT -> GradeyColors.Excellent
    GradeBand.GOOD -> GradeyColors.Good
    GradeBand.AVERAGE -> GradeyColors.Average
    GradeBand.POOR -> GradeyColors.Poor
    GradeBand.NEUTRAL -> Color.Gray
}

fun GradeBand.softColor(): Color = when (this) {
    GradeBand.NEUTRAL -> Color.Gray.copy(alpha = 0.16f)
    else -> color().copy(alpha = 0.14f)
}

fun GradeBand.gradient(): Brush {
    val base = if (this == GradeBand.NEUTRAL) GradeyColors.Primary else color()
    return Brush.linearGradient(listOf(base, base.copy(alpha = 0.78f)))
}
