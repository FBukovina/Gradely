package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.Test

class MarkDecodingTest {
    @Test
    fun `explicit null mark IDs generate distinct non-empty IDs`() {
        val marks = Json.decodeFromString<List<Mark>>(
            """[{"Id":null},{"Id":null}]""",
        )

        assertThat(marks.map(Mark::id)).doesNotContain("")
        assertThat(marks.map(Mark::id).toSet()).hasSize(2)
    }
}
