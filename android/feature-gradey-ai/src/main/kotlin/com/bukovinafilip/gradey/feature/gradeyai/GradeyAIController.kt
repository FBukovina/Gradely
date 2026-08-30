package com.bukovinafilip.gradey.feature.gradeyai

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.bukovinafilip.gradey.domain.GradeyAIContextBuilding
import com.bukovinafilip.gradey.domain.GradeyAIContextException
import com.bukovinafilip.gradey.domain.GradeyAIErrorClassifier
import com.bukovinafilip.gradey.domain.GradeyAIErrorKind
import com.bukovinafilip.gradey.domain.GradeyAIException
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAIConversation
import com.bukovinafilip.gradey.model.GradeyAIMessage
import com.bukovinafilip.gradey.model.GradeyAIMessageRole
import com.bukovinafilip.gradey.model.GradeyAIMessageStatus
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.bukovinafilip.gradey.model.GradeyAIStreamEvent
import com.bukovinafilip.gradey.model.GradeySupportTier
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.job
import kotlinx.coroutines.launch

internal data class GradeyAIFailure(
    val kind: GradeyAIErrorKind,
    val message: String = "",
    val retryable: Boolean = false,
)

internal enum class GradeyAIStarterPromptKind { IMPROVE_SUBJECT, PREPARE_SUBJECT, SUMMARIZE_MARKS, UPCOMING_TIMETABLE }

internal data class GradeyAIStarterPrompt(
    val kind: GradeyAIStarterPromptKind,
    val subject: String? = null,
)

internal class GradeyAIController(
    private val repository: GradeyAIRepository,
    private val contextBuilder: GradeyAIContextBuilding?,
    private val scope: CoroutineScope,
    private val nowEpochMillis: () -> Long = System::currentTimeMillis,
    private val idProvider: () -> String = { UUID.randomUUID().toString() },
    private val localeProvider: () -> Locale = Locale::getDefault,
) {
    var conversations by mutableStateOf<List<GradeyAIConversation>>(emptyList())
        private set
    var messages by mutableStateOf<List<GradeyAIMessage>>(emptyList())
        private set
    var status by mutableStateOf<GradeyAIStatus?>(null)
        private set
    var draft by mutableStateOf("")
    var currentConversation by mutableStateOf<GradeyAIConversation?>(null)
        private set
    var contextSnapshot by mutableStateOf<GradeyAIContextSnapshot?>(null)
        private set
    var contextFailure by mutableStateOf<GradeyAIFailure?>(null)
        private set
    var failure by mutableStateOf<GradeyAIFailure?>(null)
        private set
    var isLoading by mutableStateOf(false)
        private set
    var isStreaming by mutableStateOf(false)
        private set
    var isRefreshingContext by mutableStateOf(false)
        private set
    var isOpeningConversation by mutableStateOf(false)
        private set

    private var streamJob: Job? = null
    private var activeStreamToken: String? = null
    private var activeSchoolScope: String? = null
    private var lastFailedRequest: FailedRequest? = null
    private var draftConversationID: String? = null
    private var serverStatus: GradeyAIStatus? = null
    private var reportedDailyLimit = 0
    private var reportedUsed = 0
    private var supportTier: GradeySupportTier? = null

    val hasConsent: Boolean get() = status?.consentRequired == false
    val isDraftChat: Boolean
        get() = draftConversationID != null && currentConversation?.id == draftConversationID
    val canSend: Boolean
        get() {
            val text = draft.trim()
            return !isStreaming && text.isNotEmpty() && text.length <= MaximumPromptLength &&
                contextSnapshot != null && status?.canSend == true
        }
    val canStartNewChat: Boolean
        get() = status?.canSend == true && !isStreaming

    fun applySupportTier(value: GradeySupportTier) {
        // The server limit remains authoritative while the support catalog is unresolved.
        // A non-free entitlement can safely raise it as soon as that entitlement arrives.
        supportTier = value.takeUnless { it == GradeySupportTier.NONE }
        recomposeStatus()
    }

    suspend fun bootstrap() {
        stop()
        failure = null
        contextFailure = null
        val builder = contextBuilder
        if (builder == null) {
            val unavailable = GradeyAIFailure(
                GradeyAIErrorKind.NO_CONTEXT,
            )
            failure = unavailable
            contextFailure = unavailable
            isLoading = false
            return
        }

        try {
            val schoolScope = builder.currentSchoolScope()
            if (activeSchoolScope != null && activeSchoolScope != schoolScope) clearSchoolState()
            activeSchoolScope = schoolScope
            if (contextSnapshot == null) contextSnapshot = builder.cachedContext()
            isLoading = status == null

            coroutineScope {
                val statusAttempt = async { runCatchingSuspend { repository.loadStatus() } }
                val contextAttempt = async { runCatchingSuspend { builder.refreshContext() } }
                val conversationAttempt = async {
                    runCatchingSuspend { repository.listConversations(schoolScope) }
                }

                statusAttempt.await().fold(
                    onSuccess = { loaded ->
                        ingestStatus(loaded)
                        if (loaded.consentRequired) {
                            conversations = emptyList()
                            if (!isDraftChat) closeConversation()
                        } else {
                            conversationAttempt.await().fold(
                                onSuccess = { loadedConversations ->
                                    conversations = loadedConversations.sortedByDescending(::conversationDate)
                                    currentConversation = currentConversation?.let { selected ->
                                        loadedConversations.firstOrNull { it.id == selected.id } ?: selected
                                    }
                                },
                                onFailure = { error ->
                                    if (conversations.isEmpty() && currentConversation == null) {
                                        failure = failure(error)
                                    }
                                },
                            )
                        }
                    },
                    onFailure = { error -> if (status == null) failure = failure(error) },
                )
                contextAttempt.await().fold(
                    onSuccess = ::ingestContext,
                    onFailure = { contextFailure = failure(it) },
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            val mapped = failure(error)
            failure = mapped
            contextFailure = mapped
        } finally {
            isLoading = false
        }
    }

    suspend fun refreshStatus() {
        runCatchingSuspend { repository.loadStatus() }
            .onSuccess(::ingestStatus)
            .onFailure { failure = failure(it) }
    }

    suspend fun acceptConsent() {
        failure = null
        isLoading = true
        try {
            repository.acceptConsent()
            ingestStatus(repository.loadStatus())
            if (status?.consentRequired == false) {
                    val schoolScope = contextBuilder?.currentSchoolScope()
                        ?: throw GradeyAIException(
                            GradeyAIErrorKind.NO_CONTEXT,
                            "",
                        )
                conversations = repository.listConversations(schoolScope)
                    .sortedByDescending(::conversationDate)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            failure = failure(error)
        } finally {
            isLoading = false
        }
    }

    suspend fun revokeConsent() {
        stop()
        failure = null
        isLoading = true
        try {
            repository.revokeConsent()
            conversations = emptyList()
            messages = emptyList()
            currentConversation = null
            draftConversationID = null
            reportedUsed = 0
            (serverStatus ?: status)?.copy(
                consentRequired = true,
                dailyUsed = 0,
                remaining = status?.dailyLimit ?: 0,
            )?.let(::ingestStatus)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            failure = failure(error)
        } finally {
            isLoading = false
        }
    }

    fun beginDraftChat(localizedTitle: String) {
        stop()
        failure = null
        val schoolScope = activeSchoolScope
        if (schoolScope == null) {
            failure = GradeyAIFailure(GradeyAIErrorKind.NO_CONTEXT)
            return
        }
        val now = nowEpochMillis()
        val conversation = GradeyAIConversation(
            id = idProvider(),
            schoolScope = schoolScope,
            title = localizedTitle,
            createdAtEpochMillis = now,
            updatedAtEpochMillis = now,
        )
        draftConversationID = conversation.id
        currentConversation = conversation
        messages = emptyList()
        draft = ""
        lastFailedRequest = null
    }

    suspend fun open(conversation: GradeyAIConversation) {
        stop()
        failure = null
        draftConversationID = null
        currentConversation = conversation
        messages = emptyList()
        lastFailedRequest = null
        isOpeningConversation = true
        try {
            val detail = repository.loadConversation(conversation.id)
            currentConversation = detail.conversation
            messages = detail.messages
            upsert(detail.conversation)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            failure = failure(error)
        } finally {
            isOpeningConversation = false
        }
    }

    fun closeConversation() {
        stop()
        draftConversationID?.let { draftID ->
            conversations = conversations.filterNot { it.id == draftID }
        }
        draftConversationID = null
        currentConversation = null
        messages = emptyList()
        lastFailedRequest = null
        isOpeningConversation = false
    }

    suspend fun send(proposedText: String = draft) {
        if (isStreaming) return
        val text = proposedText.trim()
        when {
            text.isEmpty() || text.length > MaximumPromptLength -> {
                failure = GradeyAIFailure(GradeyAIErrorKind.INVALID_PROMPT)
                return
            }
            status?.enabled != true -> {
                failure = GradeyAIFailure(GradeyAIErrorKind.SERVER)
                return
            }
            status?.consentRequired != false -> {
                failure = GradeyAIFailure(GradeyAIErrorKind.SERVER)
                return
            }
            (status?.remaining ?: 0) <= 0 -> {
                failure = GradeyAIFailure(GradeyAIErrorKind.LIMIT_REACHED)
                return
            }
        }

        if (contextSnapshot == null) refreshContext()
        val context = contextSnapshot
        if (context == null) {
            failure = contextFailure ?: GradeyAIFailure(GradeyAIErrorKind.NO_CONTEXT)
            return
        }

        draft = ""
        failure = null
        val clientMessageID = idProvider()
        var conversation = currentConversation
        val needsServerCreate = conversation == null || isDraftChat
        val userMessage = GradeyAIMessage(
            id = clientMessageID,
            conversationID = conversation?.id ?: clientMessageID,
            clientMessageID = clientMessageID,
            role = GradeyAIMessageRole.USER,
            content = text,
            status = GradeyAIMessageStatus.COMPLETE,
            createdAtEpochMillis = nowEpochMillis(),
            contextGeneratedAtEpochMillis = context.generatedAtEpochMillis,
        )
        messages = messages + userMessage
        lastFailedRequest = null

        if (needsServerCreate) {
            val draftID = draftConversationID
            conversation = create(title(text), replacingCurrentChat = false)
            if (conversation != null) {
                messages = messages.map { message ->
                    if (message.id == clientMessageID) message.copy(conversationID = conversation.id) else message
                }
            }
            if (draftID != null) conversations = conversations.filterNot { it.id == draftID }
        }
        if (conversation == null) {
            messages = messages.filterNot { it.id == clientMessageID }
            draft = text
            return
        }

        updateConversationAfterMessage(conversation, title(text))
        startStream(conversation, text, clientMessageID, context)
    }

    suspend fun retry() {
        if (isStreaming) return
        val failed = lastFailedRequest ?: return
        val conversation = currentConversation?.takeIf { it.id == failed.conversationID } ?: run {
            lastFailedRequest = null
            return
        }
        val context = contextSnapshot ?: return
        if (status?.canSend != true) return
        messages = messages.filterNot {
            it.role == GradeyAIMessageRole.ASSISTANT &&
                it.status == GradeyAIMessageStatus.FAILED &&
                it.createdAtEpochMillis >= failed.startedAtEpochMillis
        }
        failure = null
        startStream(conversation, failed.text, failed.clientMessageID, context)
    }

    fun canRetry(message: GradeyAIMessage): Boolean {
        val failed = lastFailedRequest ?: return false
        return message.role == GradeyAIMessageRole.ASSISTANT &&
            message.status == GradeyAIMessageStatus.FAILED &&
            currentConversation?.id == failed.conversationID &&
            status?.canSend == true &&
            message.createdAtEpochMillis >= failed.startedAtEpochMillis
    }

    fun stop() {
        if (streamJob == null && !isStreaming) return
        activeStreamToken = null
        streamJob?.cancel()
        streamJob = null
        isStreaming = false
        messages = messages.mapIndexed { index, message ->
            if (index == messages.indexOfLast {
                    it.role == GradeyAIMessageRole.ASSISTANT && it.status == GradeyAIMessageStatus.STREAMING
                }
            ) {
                message.copy(status = GradeyAIMessageStatus.CANCELLED)
            } else {
                message
            }
        }
        lastFailedRequest = null
        scope.launch {
            delay(750)
            runCatchingSuspend { repository.loadStatus() }.onSuccess(::ingestStatus)
        }
    }

    suspend fun delete(conversation: GradeyAIConversation) {
        if (currentConversation?.id == conversation.id) stop()
        failure = null
        if (conversation.id == draftConversationID) {
            closeConversation()
            return
        }
        try {
            repository.deleteConversation(conversation.id)
            conversations = conversations.filterNot { it.id == conversation.id }
            if (currentConversation?.id == conversation.id) closeConversation()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            failure = failure(error)
        }
    }

    suspend fun deleteAll() {
        stop()
        failure = null
        try {
            val schoolScope = activeSchoolScope ?: contextBuilder?.currentSchoolScope()
                ?: throw GradeyAIException(GradeyAIErrorKind.NO_CONTEXT, "")
            repository.deleteAllConversations(schoolScope)
            conversations = emptyList()
            messages = emptyList()
            currentConversation = null
            lastFailedRequest = null
            draftConversationID = null
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            failure = failure(error)
        }
    }

    suspend fun refreshContext() {
        if (isRefreshingContext) return
        val builder = contextBuilder
        if (builder == null) {
            contextFailure = GradeyAIFailure(GradeyAIErrorKind.NO_CONTEXT)
            return
        }
        isRefreshingContext = true
        contextFailure = null
        try {
            ingestContext(builder.refreshContext())
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            contextFailure = failure(error)
        } finally {
            isRefreshingContext = false
        }
    }

    fun clearFailure() {
        failure = null
    }

    fun starterPrompts(): List<GradeyAIStarterPrompt> {
        val result = mutableListOf<GradeyAIStarterPrompt>()
        contextSnapshot?.trends?.firstOrNull { (it.averageDelta ?: 0.0) > 0.01 }?.let { trend ->
            result += GradeyAIStarterPrompt(GradeyAIStarterPromptKind.IMPROVE_SUBJECT, trend.subjectName)
        }
        contextSnapshot?.timetable?.firstOrNull()?.let { lesson ->
            result += GradeyAIStarterPrompt(GradeyAIStarterPromptKind.PREPARE_SUBJECT, lesson.subject)
        }
        result += GradeyAIStarterPrompt(GradeyAIStarterPromptKind.SUMMARIZE_MARKS)
        result += GradeyAIStarterPrompt(GradeyAIStarterPromptKind.UPCOMING_TIMETABLE)
        return result.take(3)
    }

    private suspend fun create(title: String?, replacingCurrentChat: Boolean): GradeyAIConversation? {
        return try {
            val schoolScope = activeSchoolScope ?: contextBuilder?.currentSchoolScope()
                ?: throw GradeyAIException(GradeyAIErrorKind.NO_CONTEXT, "")
            val conversation = repository.createConversation(schoolScope, title)
            upsert(conversation)
            currentConversation = conversation
            draftConversationID = null
            if (replacingCurrentChat) {
                messages = emptyList()
                lastFailedRequest = null
            }
            conversation
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            failure = failure(error)
            null
        }
    }

    private suspend fun startStream(
        conversation: GradeyAIConversation,
        text: String,
        clientMessageID: String,
        context: GradeyAIContextSnapshot,
    ) {
        val token = idProvider()
        activeStreamToken = token
        streamJob = currentCoroutineContext().job
        isStreaming = true
        val startedAt = nowEpochMillis()
        var assistantMessageID: String? = null
        var receivedTerminalEvent = false
        try {
            repository.streamReply(
                conversationID = conversation.id,
                clientMessageID = clientMessageID,
                text = text,
                context = context,
                locale = localeProvider().toLanguageTag(),
            ).collect { event ->
                if (activeStreamToken != token) return@collect
                when (event) {
                    is GradeyAIStreamEvent.Start -> {
                        assistantMessageID = event.assistantMessageID
                        updateRemaining(event.remaining)
                        messages = messages + GradeyAIMessage(
                            id = event.assistantMessageID,
                            conversationID = conversation.id,
                            role = GradeyAIMessageRole.ASSISTANT,
                            content = "",
                            status = GradeyAIMessageStatus.STREAMING,
                            createdAtEpochMillis = nowEpochMillis(),
                            contextGeneratedAtEpochMillis = context.generatedAtEpochMillis,
                        )
                    }
                    is GradeyAIStreamEvent.Delta -> assistantMessageID?.let { id ->
                        messages = messages.map { message ->
                            if (message.id == id) message.copy(content = message.content + event.text) else message
                        }
                    }
                    is GradeyAIStreamEvent.Done -> {
                        receivedTerminalEvent = true
                        updateRemaining(event.remaining)
                        val persisted = event.persistedMessage
                        when {
                            persisted != null && messages.any { it.id == persisted.id } -> {
                                messages = messages.map { if (it.id == persisted.id) persisted else it }
                            }
                            persisted != null -> {
                                assistantMessageID = persisted.id
                                messages = messages + persisted
                            }
                            assistantMessageID != null -> {
                                val id = assistantMessageID
                                messages = messages.map {
                                    if (it.id == id) it.copy(status = GradeyAIMessageStatus.COMPLETE) else it
                                }
                            }
                        }
                        lastFailedRequest = null
                        updateConversationAfterMessage(conversation, null)
                    }
                    is GradeyAIStreamEvent.Error -> {
                        receivedTerminalEvent = true
                        event.remaining?.let(::updateRemaining)
                        markAssistantFailed(assistantMessageID, conversation.id, context.generatedAtEpochMillis)
                        val mapped = GradeyAIErrorClassifier.server(
                            event.code,
                            event.message,
                            event.retryable,
                        )
                        failure = failure(mapped)
                        if (mapped.retryable) {
                            lastFailedRequest = FailedRequest(
                                conversation.id,
                                clientMessageID,
                                text,
                                startedAt,
                            )
                        }
                    }
                }
            }
            if (!receivedTerminalEvent && activeStreamToken == token) {
                throw GradeyAIException(
                    GradeyAIErrorKind.MALFORMED_RESPONSE,
                    "Gradey AI ended the reply before returning a result.",
                )
            }
        } catch (_: CancellationException) {
            assistantMessageID?.let { id ->
                messages = messages.map {
                    if (it.id == id) it.copy(status = GradeyAIMessageStatus.CANCELLED) else it
                }
            }
        } catch (error: Throwable) {
            if (activeStreamToken != token) return
            markAssistantFailed(assistantMessageID, conversation.id, context.generatedAtEpochMillis)
            val mapped = failure(error)
            failure = mapped
            if (mapped.retryable) {
                lastFailedRequest = FailedRequest(
                    conversation.id,
                    clientMessageID,
                    text,
                    startedAt,
                )
            }
        } finally {
            if (activeStreamToken == token) {
                activeStreamToken = null
                streamJob = null
                isStreaming = false
            }
        }
    }

    private fun markAssistantFailed(id: String?, conversationID: String, contextGeneratedAt: Long) {
        if (id != null && messages.any { it.id == id }) {
            messages = messages.map {
                if (it.id == id) it.copy(status = GradeyAIMessageStatus.FAILED) else it
            }
            return
        }
        messages = messages + GradeyAIMessage(
            id = id ?: idProvider(),
            conversationID = conversationID,
            role = GradeyAIMessageRole.ASSISTANT,
            content = "",
            status = GradeyAIMessageStatus.FAILED,
            createdAtEpochMillis = nowEpochMillis(),
            contextGeneratedAtEpochMillis = contextGeneratedAt,
        )
    }

    private fun ingestStatus(loaded: GradeyAIStatus) {
        serverStatus = loaded
        reportedDailyLimit = loaded.dailyLimit.coerceAtLeast(0)
        reportedUsed = maxOf(loaded.dailyUsed, (loaded.dailyLimit - loaded.remaining).coerceAtLeast(0))
        recomposeStatus()
    }

    private fun recomposeStatus() {
        val loaded = serverStatus ?: return
        val dailyLimit = supportTier?.dailyAILimit ?: reportedDailyLimit
        status = loaded.copy(
            dailyLimit = dailyLimit,
            dailyUsed = reportedUsed,
            remaining = (dailyLimit - reportedUsed).coerceAtLeast(0),
        )
    }

    private fun updateRemaining(remaining: Int) {
        reportedUsed = (reportedDailyLimit - remaining).coerceAtLeast(0)
        recomposeStatus()
    }

    private fun ingestContext(snapshot: GradeyAIContextSnapshot) {
        contextSnapshot = snapshot
        contextFailure = if (snapshot.unavailableSections.isEmpty()) {
            null
        } else {
            GradeyAIFailure(
                GradeyAIErrorKind.NO_CONTEXT,
            )
        }
    }

    private fun updateConversationAfterMessage(conversation: GradeyAIConversation, title: String?) {
        var updated = currentConversation?.takeIf { it.id == conversation.id } ?: conversation
        if (title != null && (updated.title.isBlank() || updated.id == draftConversationID)) {
            updated = updated.copy(title = title)
        }
        val now = nowEpochMillis()
        updated = updated.copy(updatedAtEpochMillis = now, lastMessageAtEpochMillis = now)
        currentConversation = updated
        upsert(updated)
    }

    private fun upsert(conversation: GradeyAIConversation) {
        conversations = (conversations.filterNot { it.id == conversation.id } + conversation)
            .sortedByDescending(::conversationDate)
    }

    private fun clearSchoolState() {
        conversations = emptyList()
        messages = emptyList()
        currentConversation = null
        draftConversationID = null
        status = null
        serverStatus = null
        reportedDailyLimit = 0
        reportedUsed = 0
        lastFailedRequest = null
        contextSnapshot = null
    }

    private fun failure(error: Throwable): GradeyAIFailure = when (error) {
        is GradeyAIException -> GradeyAIFailure(error.kind, error.message.orEmpty(), error.retryable)
        is GradeyAIContextException -> GradeyAIFailure(GradeyAIErrorKind.NO_CONTEXT)
        else -> GradeyAIFailure(
            GradeyAIErrorKind.TRANSPORT,
            retryable = true,
        )
    }

    private suspend fun <T> runCatchingSuspend(block: suspend () -> T): Result<T> = try {
        Result.success(block())
    } catch (error: CancellationException) {
        throw error
    } catch (error: Throwable) {
        Result.failure(error)
    }

    private fun title(text: String): String = text.split(Regex("\\s+"))
        .filter(String::isNotBlank)
        .joinToString(" ")
        .take(60)

    private fun conversationDate(value: GradeyAIConversation): Long =
        value.lastMessageAtEpochMillis ?: value.updatedAtEpochMillis

    private data class FailedRequest(
        val conversationID: String,
        val clientMessageID: String,
        val text: String,
        val startedAtEpochMillis: Long,
    )

    private companion object {
        const val MaximumPromptLength = 2_000
    }
}
