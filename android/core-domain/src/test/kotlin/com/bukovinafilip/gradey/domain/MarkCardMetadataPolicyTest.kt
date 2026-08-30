package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Mark
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class MarkCardMetadataPolicyTest {
    @Test
    fun `caption theme and type follow the iOS fallback rules`() {
        val metadata = metadata(
            mark = Mark(
                caption = "  Written exam  ",
                theme = "  Fractions  ",
                type = "Final",
                typeNote = "  Midterm  ",
            ),
        )

        assertThat(metadata.caption).isEqualTo("Written exam")
        assertThat(metadata.theme).isEqualTo("Fractions")
        assertThat(metadata.typeLabel).isEqualTo("Midterm")
    }

    @Test
    fun `theme becomes the title only when caption is unavailable`() {
        val themeFallback = metadata(Mark(caption = " ", theme = " Project ", typeNote = " ", type = "Other"))
        val untitledFallback = metadata(Mark(caption = null, theme = "", type = ""))
        val duplicateTheme = metadata(Mark(caption = "Quiz", theme = " Quiz "))

        assertThat(themeFallback.caption).isEqualTo("Project")
        assertThat(themeFallback.theme).isNull()
        assertThat(themeFallback.typeLabel).isEqualTo("Other")
        assertThat(untitledFallback.caption).isEqualTo("Untitled")
        assertThat(untitledFallback.typeLabel).isNull()
        assertThat(duplicateTheme.theme).isNull()
    }

    @Test
    fun `only meaningful explicit and inferred weights receive badges`() {
        val mark = Mark(weight = 3.0)

        assertThat(metadata(mark, ResolvedMarkWeight(3.0, MarkWeightSource.EXPLICIT)).weightBadge)
            .isEqualTo(MarkWeightBadge(3.0, MarkWeightBadgeKind.EXPLICIT))
        assertThat(metadata(mark, ResolvedMarkWeight(2.0, MarkWeightSource.INFERRED)).weightBadge)
            .isEqualTo(MarkWeightBadge(2.0, MarkWeightBadgeKind.ESTIMATED))
        assertThat(metadata(mark, ResolvedMarkWeight(1.0, MarkWeightSource.EXPLICIT)).weightBadge).isNull()
        assertThat(metadata(mark, ResolvedMarkWeight(4.0, MarkWeightSource.FALLBACK)).weightBadge).isNull()
    }

    @Test
    fun `points and new-state metadata are preserved without a weight badge`() {
        val pointMetadata = metadata(
            mark = Mark(markText = "17", isPoints = true, maxPoints = 20, isNew = true),
            weight = ResolvedMarkWeight(5.0, MarkWeightSource.EXPLICIT),
        )

        assertThat(pointMetadata.pointsLabel).isEqualTo("17/20")
        assertThat(pointMetadata.weightBadge).isNull()
        assertThat(pointMetadata.isNew).isTrue()
        assertThat(metadata(Mark(markText = "17", isPoints = true)).pointsLabel).isNull()
    }

    private fun metadata(
        mark: Mark,
        weight: ResolvedMarkWeight = ResolvedMarkWeight(1.0, MarkWeightSource.FALLBACK),
    ): MarkCardMetadata = MarkCardMetadataPolicy.resolve(mark, weight, "Untitled")
}
