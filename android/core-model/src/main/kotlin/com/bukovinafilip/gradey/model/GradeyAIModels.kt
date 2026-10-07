package com.bukovinafilip.gradey.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class GradeyAIConversation(
    val id: String,
    @SerialName("school_scope") val schoolScope: String,
    val title: String,
    @SerialName("created_at") val createdAtEpochMillis: Long,
    @SerialName("updated_at") val updatedAtEpochMillis: Long,
    @SerialName("last_message_at") val lastMessageAtEpochMillis: Long? = null,
)

@Serializable
enum class GradeyAIMessageRole {
    @SerialName("user") USER,
    @SerialName("assistant") ASSISTANT,
}

@Serializable
enum class GradeyAIMessageStatus {
    @SerialName("streaming") STREAMING,
    @SerialName("complete") COMPLETE,
    @SerialName("cancelled") CANCELLED,
    @SerialName("failed") FAILED,
}

@Serializable
data class GradeyAIMessage(
    val id: String,
    @SerialName("conversation_id") val conversationID: String,
    @SerialName("client_message_id") val clientMessageID: String? = null,
    val role: GradeyAIMessageRole,
    val content: String,
    val status: GradeyAIMessageStatus,
    @SerialName("created_at") val createdAtEpochMillis: Long,
    @SerialName("context_generated_at") val contextGeneratedAtEpochMillis: Long? = null,
)

@Serializable
enum class GradeyAIContextSection {
    @SerialName("marks") MARKS,
    @SerialName("trends") TRENDS,
    @SerialName("timetable") TIMETABLE,
}

@Serializable
data class GradeyAIMarkContext(
    val value: String,
    val date: String,
    val weight: Double? = null,
    val title: String? = null,
    @SerialName("is_points") val isPoints: Boolean,
    @SerialName("points_text") val pointsText: String? = null,
    @SerialName("max_points") val maxPoints: Int? = null,
)

@Serializable
data class GradeyAISubjectContext(
    val id: String,
    val name: String,
    val abbreviation: String? = null,
    val average: Double? = null,
    @SerialName("points_only") val pointsOnly: Boolean,
    @SerialName("total_mark_count") val totalMarkCount: Int,
    @SerialName("recent_marks") val recentMarks: List<GradeyAIMarkContext>,
)

@Serializable
data class GradeyAITrendContext(
    @SerialName("subject_id") val subjectID: String,
    @SerialName("subject_name") val subjectName: String,
    @SerialName("subject_abbreviation") val subjectAbbreviation: String? = null,
    @SerialName("first_average") val firstAverage: Double? = null,
    @SerialName("latest_average") val latestAverage: Double? = null,
    @SerialName("average_delta") val averageDelta: Double? = null,
    @SerialName("first_mark_count") val firstMarkCount: Int,
    @SerialName("latest_mark_count") val latestMarkCount: Int,
)

@Serializable
enum class GradeyAILessonChangeKind {
    @SerialName("none") NONE,
    @SerialName("cancelled") CANCELLED,
    @SerialName("substitution") SUBSTITUTION,
    @SerialName("room_changed") ROOM_CHANGED,
    @SerialName("added") ADDED,
}

@Serializable
data class GradeyAILessonContext(
    val id: String,
    val date: String,
    val subject: String,
    @SerialName("subject_abbreviation") val subjectAbbreviation: String? = null,
    @SerialName("begins_at") val beginsAt: String,
    @SerialName("ends_at") val endsAt: String,
    val teacher: String? = null,
    val room: String? = null,
    val groups: List<String>,
    @SerialName("change_kind") val changeKind: GradeyAILessonChangeKind,
    @SerialName("change_description") val changeDescription: String? = null,
)

@Serializable
data class GradeyAIContextSnapshot(
    @SerialName("school_scope") val schoolScope: String,
    @SerialName("generated_at") val generatedAtEpochMillis: Long,
    @SerialName("is_stale") val isStale: Boolean,
    @SerialName("unavailable_sections") val unavailableSections: List<GradeyAIContextSection>,
    val subjects: List<GradeyAISubjectContext>,
    val trends: List<GradeyAITrendContext>,
    val timetable: List<GradeyAILessonContext>,
) {
    val isPartial: Boolean get() = unavailableSections.isNotEmpty()
}

sealed interface GradeyAIStreamEvent {
    data class Start(
        val assistantMessageID: String,
        val remaining: Int,
    ) : GradeyAIStreamEvent

    data class Delta(val text: String) : GradeyAIStreamEvent

    data class Done(
        val finishReason: String?,
        val remaining: Int,
        val inputTokens: Int?,
        val outputTokens: Int?,
        val persistedMessage: GradeyAIMessage?,
    ) : GradeyAIStreamEvent

    data class Error(
        val code: String,
        val message: String,
        val retryable: Boolean,
        val remaining: Int?,
    ) : GradeyAIStreamEvent
}

data class GradeyAIConversationDetail(
    val conversation: GradeyAIConversation,
    val messages: List<GradeyAIMessage>,
)
