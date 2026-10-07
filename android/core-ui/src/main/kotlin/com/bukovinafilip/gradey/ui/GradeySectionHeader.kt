package com.bukovinafilip.gradey.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import java.util.Locale

/** Typography shared by section headers in the SwiftUI and Compose design systems. */
object GradeySectionHeaderTokens {
    val FontSize = 13.sp
    val LineHeight = 18.sp
    val LetterSpacing = 0.6.sp
}

/** Returns the locale-aware uppercase label used by a Gradey section header. */
fun gradeySectionHeaderText(text: String, locale: Locale): String = text.uppercase(locale)

/** Small uppercase tracked label used to separate content sections. */
@Composable
fun GradeySectionHeader(
    text: String,
    modifier: Modifier = Modifier,
) {
    val locale = LocalConfiguration.current.locales[0]

    Text(
        text = gradeySectionHeaderText(text, locale),
        modifier = modifier
            .fillMaxWidth()
            .semantics { heading() },
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontSize = GradeySectionHeaderTokens.FontSize,
        lineHeight = GradeySectionHeaderTokens.LineHeight,
        letterSpacing = GradeySectionHeaderTokens.LetterSpacing,
        fontWeight = FontWeight.Bold,
    )
}
