package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.SerializationException
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

    @Test
    fun `explicit null mark date and type normalize to empty strings`() {
        val mark = Json.decodeFromString<Mark>(
            """{"MarkDate":null,"Type":null}""",
        )

        assertThat(mark.markDate).isEmpty()
        assertThat(mark.type).isEmpty()
    }

    @Test
    fun `mark date and type reject non-string non-null values`() {
        listOf(
            """{"MarkDate":7}""",
            """{"MarkDate":{}}""",
            """{"Type":false}""",
            """{"Type":[]}""",
        ).forEach { payload ->
            val failure = runCatching { Json.decodeFromString<Mark>(payload) }.exceptionOrNull()

            assertThat(failure).isInstanceOf(SerializationException::class.java)
        }
    }
}
