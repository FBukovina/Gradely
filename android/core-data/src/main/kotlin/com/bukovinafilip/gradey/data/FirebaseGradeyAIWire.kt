package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.GradeyAIErrorKind
import com.bukovinafilip.gradey.domain.GradeyAIException
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAIConversation
import com.bukovinafilip.gradey.model.GradeyAIConversationDetail
import com.bukovinafilip.gradey.model.GradeyAIMessage
import com.bukovinafilip.gradey.model.GradeyAIMessageRole
import com.bukovinafilip.gradey.model.GradeyAIMessageStatus
import com.bukovinafilip.gradey.model.GradeyAIStreamEvent
import java.time.Instant
import java.time.format.DateTimeParseException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

internal object FirebaseGradeyAIWire {
    fun decodeConversations(payload: Any?): List<GradeyAIConversation> {
        val envelope = payload.objectValue("conversation list")
        val values = envelope.value("chats", "conversations", "items")
            ?: return emptyList()
        return values.objectList("conversation list").map(::decodeConversation)
            .sortedByDescending { it.lastMessageAtEpochMillis ?: it.updatedAtEpochMillis }
    }

    fun decodeConversationEnvelope(payload: Any?): GradeyAIConversation {
        val envelope = payload.objectValue("conversation")
        return decodeConversation(
            envelope.value("chat", "conversation")?.objectValue("conversation") ?: envelope,
        )
    }

    fun decodeConversationDetail(payload: Any?, fallbackConversationID: String): GradeyAIConversationDetail {
        val envelope = payload.objectValue("conversation detail")
        val conversation = decodeConversation(
            envelope.value("chat", "conversation")?.objectValue("conversation")
                ?: throw malformed("Gradey AI returned a conversation detail without a conversation."),
        )
        val messages = envelope.value("messages", "history", "items")
            ?.objectList("message history")
            .orEmpty()
            .map { decodeMessage(it, fallbackConversationID) }
            .sortedBy(GradeyAIMessage::createdAtEpochMillis)
        return GradeyAIConversationDetail(conversation, messages)
    }

    fun decodeStreamEvent(payload: Any?, fallbackConversationID: String): GradeyAIStreamEvent {
        val values = payload.objectValue("stream event")
        return when (values.string("type")?.lowercase()) {
            "started", "start" -> {
                val messageID = values.string("assistantMessageID", "assistant_message_id")
                    ?: throw malformed("Gradey AI started a reply without a message identifier.")
                val remaining = values.statusRemaining()
                    ?: throw malformed("Gradey AI started a reply without usage status.")
                GradeyAIStreamEvent.Start(messageID, remaining)
            }

            "delta" -> GradeyAIStreamEvent.Delta(
                values.string("text")
                    ?: throw malformed("Gradey AI returned an invalid reply fragment."),
            )

            "completed", "done" -> {
                val remaining = values.statusRemaining()
                    ?: throw malformed("Gradey AI completed a reply without usage status.")
                val usage = values.value("usage") as? Map<*, *>
                val persisted = (values.value("message", "persistedMessage", "persisted_message") as? Map<*, *>)
                    ?.let { decodeMessage(it, fallbackConversationID) }
                GradeyAIStreamEvent.Done(
                    finishReason = values.string("finishReason", "finish_reason") ?: "stop",
                    remaining = remaining,
                    inputTokens = usage?.integer("inputTokens", "input_tokens"),
                    outputTokens = usage?.integer("outputTokens", "output_tokens"),
                    persistedMessage = persisted,
                )
            }

            "failed", "error" -> {
                val messageValue = values.value("message")
                GradeyAIStreamEvent.Error(
                    code = values.string("code")
                        ?: throw malformed("Gradey AI returned an error without a code."),
                    message = when (messageValue) {
                        is String -> messageValue
                        is Map<*, *> -> messageValue.string("message", "text", "content")
                        else -> values.string("text")
                    } ?: throw malformed("Gradey AI returned an error without a message."),
                    retryable = values.boolean("retryable") ?: false,
                    remaining = values.statusRemaining(),
                )
            }

            else -> throw malformed("Gradey AI returned an unsupported stream event.")
        }
    }

    private fun decodeConversation(values: Map<*, *>): GradeyAIConversation {
        val now = System.currentTimeMillis()
        val id = values.string("id", "chatID", "chatId", "chat_id")
            ?.takeIf(String::isNotBlank)
            ?: throw malformed("Gradey AI returned a conversation without an identifier.")
        val createdAt = values.epochMillis("createdAt", "created_at") ?: now
        return GradeyAIConversation(
            id = id,
            schoolScope = values.string("schoolScope", "school_scope").orEmpty(),
            title = values.string("title").orEmpty(),
            createdAtEpochMillis = createdAt,
            updatedAtEpochMillis = values.epochMillis("updatedAt", "updated_at") ?: createdAt,
            lastMessageAtEpochMillis = values.epochMillis("lastMessageAt", "last_message_at"),
        )
    }

    private fun decodeMessage(values: Map<*, *>, fallbackConversationID: String): GradeyAIMessage {
        val id = values.string("id", "messageID", "messageId", "message_id")
            ?.takeIf(String::isNotBlank)
            ?: throw malformed("Gradey AI returned a message without an identifier.")
        return GradeyAIMessage(
            id = id,
            conversationID = values.string(
                "conversationID", "conversationId", "conversation_id", "chatID", "chatId", "chat_id",
            ) ?: fallbackConversationID,
            clientMessageID = values.string("clientMessageID", "clientMessageId", "client_message_id"),
            role = if (values.string("role")?.lowercase() == "user") {
                GradeyAIMessageRole.USER
            } else {
                GradeyAIMessageRole.ASSISTANT
            },
            content = values.string("content", "text").orEmpty(),
            status = when (values.string("status", "state")?.lowercase()) {
                "pending", "streaming" -> GradeyAIMessageStatus.STREAMING
                "cancelled", "canceled" -> GradeyAIMessageStatus.CANCELLED
                "failed" -> GradeyAIMessageStatus.FAILED
                else -> GradeyAIMessageStatus.COMPLETE
            },
            createdAtEpochMillis = values.epochMillis("createdAt", "created_at") ?: System.currentTimeMillis(),
            contextGeneratedAtEpochMillis = values.epochMillis(
                "contextGeneratedAt", "context_generated_at",
            ),
        )
    }

    private fun Map<*, *>.statusRemaining(): Int? = integer("remaining")
        ?: (value("status") as? Map<*, *>)?.integer("remaining")
}

internal object FirebaseGradeyAIRequestBuilder {
    const val MaximumPromptLength = 2_000
    const val MaximumContextBytes = 96 * 1_024
    const val MaximumRequestBytes = 128 * 1_024

    fun streamPayload(
        conversationID: String,
        clientMessageID: String,
        text: String,
        locale: String,
        context: GradeyAIContextSnapshot,
        gradeyAccountID: String?,
    ): Map<String, Any?> {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || trimmed.length > MaximumPromptLength) {
            throw GradeyAIException(
                GradeyAIErrorKind.INVALID_PROMPT,
                "Enter a message between 1 and 2,000 characters.",
            )
        }
        val minimizedContext = constrainedContext(context)
        val payload = buildMap<String, Any?> {
            put("chatID", conversationID)
            put("clientMessageID", clientMessageID)
            put("text", trimmed)
            put("locale", locale)
            put("schoolScope", context.schoolScope)
            put("context", minimizedContext)
            put("contextGeneratedAt", context.generatedAtEpochMillis.toDouble())
            gradeyAccountID?.let { put("gradey_account_id", it) }
        }
        if (encodedSize(payload) > MaximumRequestBytes) throw requestTooLarge()
        return payload
    }

    fun constrainedContext(
        snapshot: GradeyAIContextSnapshot,
        maximumBytes: Int = MaximumContextBytes,
    ): Map<String, Any?> {
        val subjects = snapshot.subjects.map { subject ->
            linkedMapOf<String, Any?>(
                "id" to subject.id,
                "name" to subject.name,
                "abbreviation" to subject.abbreviation,
                "average" to subject.average,
                "pointsOnly" to subject.pointsOnly,
                "totalMarkCount" to subject.totalMarkCount,
                "recentMarks" to subject.recentMarks.map { mark ->
                    linkedMapOf<String, Any?>(
                        "value" to mark.value,
                        "date" to mark.date,
                        "weight" to mark.weight,
                        "title" to mark.title,
                        "isPoints" to mark.isPoints,
                        "pointsText" to mark.pointsText,
                        "maxPoints" to mark.maxPoints,
                    )
                }.toMutableList(),
            )
        }.toMutableList()
        val trends = snapshot.trends.map { trend ->
            linkedMapOf<String, Any?>(
                "subjectID" to trend.subjectID,
                "subjectName" to trend.subjectName,
                "subjectAbbreviation" to trend.subjectAbbreviation,
                "firstAverage" to trend.firstAverage,
                "latestAverage" to trend.latestAverage,
                "averageDelta" to trend.averageDelta,
                "firstMarkCount" to trend.firstMarkCount,
                "latestMarkCount" to trend.latestMarkCount,
            )
        }.toMutableList()
        val timetable = snapshot.timetable.map { lesson ->
            linkedMapOf<String, Any?>(
                "id" to lesson.id,
                "date" to lesson.date,
                "subject" to lesson.subject,
                "subjectAbbreviation" to lesson.subjectAbbreviation,
                "beginsAt" to lesson.beginsAt,
                "endsAt" to lesson.endsAt,
                "teacher" to lesson.teacher,
                "room" to lesson.room,
                "groups" to lesson.groups,
                "changeKind" to lesson.changeKind.name.lowercase(),
                "changeDescription" to lesson.changeDescription,
            )
        }.toMutableList()
        val context = linkedMapOf<String, Any?>(
            "schoolScope" to snapshot.schoolScope,
            "generatedAt" to snapshot.generatedAtEpochMillis.toDouble(),
            "isStale" to snapshot.isStale,
            "unavailableSections" to snapshot.unavailableSections.map { it.name.lowercase() },
            "subjects" to subjects,
            "trends" to trends,
            "timetable" to timetable,
        )

        while (encodedSize(context) > maximumBytes) {
            when {
                timetable.isNotEmpty() -> timetable.removeAt(timetable.lastIndex)
                subjects.any { (it["recentMarks"] as MutableList<*>).isNotEmpty() } -> {
                    @Suppress("UNCHECKED_CAST")
                    val marks = subjects
                        .map { it["recentMarks"] as MutableList<Map<String, Any?>> }
                        .maxBy { it.size }
                    marks.removeAt(marks.lastIndex)
                }
                trends.isNotEmpty() -> trends.removeAt(trends.lastIndex)
                subjects.isNotEmpty() -> subjects.removeAt(subjects.lastIndex)
                else -> throw requestTooLarge()
            }
        }
        return context
    }

    internal fun encodedSize(value: Any?): Int = Json.encodeToString(
        JsonElement.serializer(),
        value.toJsonElement(),
    ).encodeToByteArray().size

    private fun requestTooLarge() = GradeyAIException(
        GradeyAIErrorKind.REQUEST_TOO_LARGE,
        "The selected school context is too large to send. Refresh it and try again.",
    )
}

private fun Any?.objectValue(name: String): Map<*, *> = this as? Map<*, *>
    ?: throw malformed("Gradey AI returned an invalid $name response.")

private fun Any?.objectList(name: String): List<Map<*, *>> = when (this) {
    is List<*> -> map { it.objectValue(name) }
    is Map<*, *> -> values.map { it.objectValue(name) }
    else -> throw malformed("Gradey AI returned an invalid $name response.")
}

private fun Map<*, *>.value(vararg names: String): Any? = names.firstNotNullOfOrNull { this[it] }

internal fun Map<*, *>.string(vararg names: String): String? = when (val value = value(*names)) {
    is String -> value
    is Number, is Boolean -> value.toString()
    else -> null
}

internal fun Map<*, *>.boolean(vararg names: String): Boolean? = when (val value = value(*names)) {
    is Boolean -> value
    is Number -> value.toInt() != 0
    is String -> value.toBooleanStrictOrNull() ?: value.toIntOrNull()?.let { it != 0 }
    else -> null
}

internal fun Map<*, *>.integer(vararg names: String): Int? = when (val value = value(*names)) {
    is Number -> value.toInt()
    is String -> value.toDoubleOrNull()?.toInt()
    else -> null
}

internal fun Map<*, *>.number(vararg names: String): Double? = when (val value = value(*names)) {
    is Number -> value.toDouble()
    is String -> value.toDoubleOrNull()
    else -> null
}

internal fun Map<*, *>.epochMillis(vararg names: String): Long? = value(*names).toEpochMillis()

internal fun Any?.toEpochMillis(): Long? = when (this) {
    is Number -> normalizeEpoch(toDouble())
    is String -> toDoubleOrNull()?.let(::normalizeEpoch) ?: try {
        Instant.parse(this).toEpochMilli()
    } catch (_: DateTimeParseException) {
        null
    }
    is Map<*, *> -> {
        number("milliseconds", "millis", "value")?.let(::normalizeEpoch)
            ?: number("_seconds", "seconds")?.let { seconds ->
                (seconds * 1_000 + (number("_nanoseconds", "nanoseconds") ?: 0.0) / 1_000_000).toLong()
            }
    }
    else -> null
}

private fun normalizeEpoch(value: Double): Long = if (kotlin.math.abs(value) < 10_000_000_000) {
    (value * 1_000).toLong()
} else {
    value.toLong()
}

private fun Any?.toJsonElement(): JsonElement = when (this) {
    null -> JsonNull
    is JsonElement -> this
    is Map<*, *> -> JsonObject(entries.associate { (key, value) -> key.toString() to value.toJsonElement() })
    is Iterable<*> -> JsonArray(map { it.toJsonElement() })
    is Array<*> -> JsonArray(map { it.toJsonElement() })
    is Boolean -> JsonPrimitive(this)
    is Number -> JsonPrimitive(this)
    else -> JsonPrimitive(toString())
}

private fun malformed(message: String, cause: Throwable? = null) = GradeyAIException(
    kind = GradeyAIErrorKind.MALFORMED_RESPONSE,
    message = message,
    cause = cause,
)
