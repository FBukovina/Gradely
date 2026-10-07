package com.bukovinafilip.gradey.feature.gradeyai

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class GradeyAIMarkdownTest {
    @Test
    fun `parser preserves headings paragraphs and unordered or numbered lists`() {
        val blocks = GradeyAIMarkdown.blocks(
            """
            ## Focus

            Your **math** trend is improving.
            Keep going.

            - Review algebra
            2. Practise fractions
            """.trimIndent(),
        )

        assertThat(blocks).containsExactly(
            GradeyAIMarkdownBlock.Heading("Focus", 2),
            GradeyAIMarkdownBlock.Paragraph("Your **math** trend is improving.\nKeep going."),
            GradeyAIMarkdownBlock.ListItems(listOf("Review algebra", "Practise fractions")),
        ).inOrder()
    }

    @Test
    fun `inline renderer keeps safe text but does not create executable links`() {
        val rendered = GradeyAIMarkdown.inline(
            "Read **carefully**, use `notes`, then [verify](https://example.com).",
        )

        assertThat(rendered.text).isEqualTo(
            "Read carefully, use notes, then verify (https://example.com).",
        )
        assertThat(rendered.getStringAnnotations(0, rendered.length)).isEmpty()
        assertThat(rendered.spanStyles).hasSize(2)
    }

    @Test
    fun `control characters are removed from assistant markdown`() {
        val blocks = GradeyAIMarkdown.blocks("Safe\u0000 text\n\n- Item\u0007")

        assertThat(blocks).containsExactly(
            GradeyAIMarkdownBlock.Paragraph("Safe text"),
            GradeyAIMarkdownBlock.ListItems(listOf("Item")),
        ).inOrder()
    }
}
