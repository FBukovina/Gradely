package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Test

class GradeyAIModelsTest {
    @Test
    fun `context model preserves partial stale and snake case wire semantics`() {
        val snapshot = GradeyAIContextSnapshot(
            schoolScope = "scope-hash",
            generatedAtEpochMillis = 1_700_000_000_000,
            isStale = true,
            unavailableSections = listOf(GradeyAIContextSection.TRENDS),
            subjects = emptyList(),
            trends = emptyList(),
            timetable = emptyList(),
        )

        val encoded = Json.encodeToString(snapshot)

        assertThat(snapshot.isPartial).isTrue()
        assertThat(encoded).contains("\"school_scope\":\"scope-hash\"")
        assertThat(encoded).contains("\"is_stale\":true")
        assertThat(encoded).contains("\"unavailable_sections\":[\"trends\"]")
    }

    @Test
    fun `conversation messages and all stream event shapes retain their identity`() {
        val conversation = GradeyAIConversation("chat", "scope", "Math", 1, 2, 3)
        val message = GradeyAIMessage(
            id = "message",
            conversationID = conversation.id,
            clientMessageID = "client-message",
            role = GradeyAIMessageRole.ASSISTANT,
            content = "Answer",
            status = GradeyAIMessageStatus.COMPLETE,
            createdAtEpochMillis = 4,
            contextGeneratedAtEpochMillis = 5,
        )
        val events = listOf(
            GradeyAIStreamEvent.Start(message.id, 4),
            GradeyAIStreamEvent.Delta("Ans"),
            GradeyAIStreamEvent.Done("stop", 3, 10, 20, message),
            GradeyAIStreamEvent.Error("over_limit", "Limit reached", false, 0),
        )

        assertThat(GradeyAIConversationDetail(conversation, listOf(message)).messages).containsExactly(message)
        assertThat(events).hasSize(4)
        assertThat((events[2] as GradeyAIStreamEvent.Done).persistedMessage).isEqualTo(message)
    }
}
