package com.bukovinafilip.gradey.feature.gradeyai

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

internal sealed interface GradeyAIMarkdownBlock {
    data class Heading(val text: String, val level: Int) : GradeyAIMarkdownBlock
    data class Paragraph(val text: String) : GradeyAIMarkdownBlock
    data class ListItems(val items: List<String>) : GradeyAIMarkdownBlock
}

internal object GradeyAIMarkdown {
    fun blocks(markdown: String): List<GradeyAIMarkdownBlock> {
        val normalized = markdown
            .replace("\r\n", "\n")
            .replace('\r', '\n')
            .filter { it == '\n' || it == '\t' || !it.isISOControl() }
        val blocks = mutableListOf<GradeyAIMarkdownBlock>()
        val paragraph = mutableListOf<String>()
        val list = mutableListOf<String>()

        fun flushParagraph() {
            paragraph.joinToString("\n").trim().takeIf(String::isNotEmpty)?.let {
                blocks += GradeyAIMarkdownBlock.Paragraph(it)
            }
            paragraph.clear()
        }

        fun flushList() {
            if (list.isNotEmpty()) blocks += GradeyAIMarkdownBlock.ListItems(list.toList())
            list.clear()
        }

        normalized.split('\n').forEach { rawLine ->
            val line = rawLine.trim()
            val heading = Heading.matchEntire(line)
            val item = Bullet.matchEntire(line) ?: Numbered.matchEntire(line)
            when {
                heading != null -> {
                    flushParagraph()
                    flushList()
                    val text = heading.groupValues[2].trim().trimEnd('#').trim()
                    if (text.isNotEmpty()) {
                        blocks += GradeyAIMarkdownBlock.Heading(text, heading.groupValues[1].length)
                    }
                }
                item != null -> {
                    flushParagraph()
                    list += item.groupValues[1]
                }
                line.isEmpty() -> {
                    flushParagraph()
                    flushList()
                }
                else -> {
                    flushList()
                    paragraph += rawLine
                }
            }
        }
        flushParagraph()
        flushList()
        return blocks
    }

    fun inline(markdown: String): AnnotatedString = buildAnnotatedString {
        val safe = markdown
            .filter { it == '\n' || it == '\t' || !it.isISOControl() }
            .replace(Link) { match -> "${match.groupValues[1]} (${match.groupValues[2]})" }
        var index = 0
        while (index < safe.length) {
            val token = InlineToken.find(safe, index)
            if (token == null) {
                append(safe.substring(index))
                break
            }
            append(safe.substring(index, token.range.first))
            val marker = token.groupValues[1]
            val content = token.groupValues[2]
            val style = when (marker) {
                "**", "__" -> SpanStyle(fontWeight = FontWeight.Bold)
                "*", "_" -> SpanStyle(fontStyle = FontStyle.Italic)
                "`" -> SpanStyle(fontFamily = FontFamily.Monospace)
                else -> SpanStyle()
            }
            pushStyle(style)
            append(content)
            pop()
            index = token.range.last + 1
        }
    }

    private val Heading = Regex("^(#{1,6})\\s+(.+?)\\s*$")
    private val Bullet = Regex("^[-*+]\\s+(.+)$")
    private val Numbered = Regex("^\\d+[.)]\\s+(.+)$")
    private val Link = Regex("\\[([^]\\n]+)]\\((https?://[^)\\s]+)\\)")
    private val InlineToken = Regex("(\\*\\*|__|`|\\*|_)(.+?)\\1")
}

@Composable
internal fun GradeyAIMarkdownText(
    markdown: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        GradeyAIMarkdown.blocks(markdown).forEach { block ->
            when (block) {
                is GradeyAIMarkdownBlock.Heading -> Text(
                    text = GradeyAIMarkdown.inline(block.text),
                    style = if (block.level <= 2) {
                        MaterialTheme.typography.titleMedium
                    } else {
                        MaterialTheme.typography.bodyLarge
                    },
                    fontWeight = FontWeight.SemiBold,
                )
                is GradeyAIMarkdownBlock.Paragraph -> Text(
                    text = GradeyAIMarkdown.inline(block.text),
                    style = MaterialTheme.typography.bodyMedium,
                )
                is GradeyAIMarkdownBlock.ListItems -> Column(
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    block.items.forEach { item ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                "•",
                                color = MaterialTheme.colorScheme.primary,
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                text = GradeyAIMarkdown.inline(item),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                }
            }
        }
    }
}
