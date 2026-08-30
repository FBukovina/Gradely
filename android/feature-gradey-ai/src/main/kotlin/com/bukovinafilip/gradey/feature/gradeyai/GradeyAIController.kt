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
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

internal data class GradeyAIFailure(
    val kind: GradeyAIErrorKind,
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
    var isSending by mutableStateOf(false)
        private set
    var isRefreshingContext by mutableStateOf(false)
        private set
    var isOpeningConversation by mutableStateOf(false)
        private set
    var isPerformingDestructiveOperation by mutableStateOf(false)
        private set
    var isAppForegrounded by mutableStateOf(true)
        private set

    private var sendJob: Job? = null
    private var activeSendToken: String? = null
    private var openJob: Job? = null
    private var activeOpenToken: String? = null
    private var activeContextRefreshToken: String? = null
    private var foregroundGeneration = 0
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
            return isAppForegrounded && !isSending && !isOpeningConversation &&
                !isPerformingDestructiveOperation &&
                text.isNotEmpty() && text.length <= MaximumPromptLength &&
                contextSnapshot != null && status?.canSend == true
        }
    val canStartNewChat: Boolean
        get() = isAppForegrounded && status?.canSend == true && !isSending &&
            !isPerformingDestructiveOperation

    fun onAppBackgrounded() {
        if (!isAppForegrounded) return
        isAppForegrounded = false
        foregroundGeneration += 1
        activeContextRefreshToken = null
        isRefreshingContext = false
        cancelOpen()
        stop(reconcileStatus = false)
        if (!isPerformingDestructiveOperation) isLoading = false
    }

    /** Returns true only for the first foreground transition after a background event. */
    fun onAppForegrounded(): Boolean {
        if (isAppForegrounded) return false
        isAppForegrounded = true
        return true
    }

    fun applySupportTier(value: GradeySupportTier) {
        // The server limit remains authoritative while the support catalog is unresolved.
        // A non-free entitlement can safely raise it as soon as that entitlement arrives.
        supportTier = value.takeUnless { it == GradeySupportTier.NONE }
        recomposeStatus()
    }

    suspend fun bootstrap() {
        if (!isAppForegrounded || isPerformingDestructiveOperation) return
        val generation = foregroundGeneration
        cancelOpen()
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
            if (!isCurrentForegroundOperation(generation)) return
            if (activeSchoolScope != null && activeSchoolScope != schoolScope) clearSchoolState()
            activeSchoolScope = schoolScope
            if (contextSnapshot == null) {
                val cachedContext = builder.cachedContext()
                if (!isCurrentForegroundOperation(generation)) return
                contextSnapshot = cachedContext
            }
            isLoading = status == null

            coroutineScope {
                val statusAttempt = async { runCatchingSuspend { repository.loadStatus() } }
                val contextAttempt = async { runCatchingSuspend { builder.refreshContext() } }
                val conversationAttempt = async {
                    runCatchingSuspend { repository.listConversations(schoolScope) }
                }

                val loadedStatus = statusAttempt.await()
                val loadedContext = contextAttempt.await()
                val loadedConversations = conversationAttempt.await()
                if (!isCurrentForegroundOperation(generation)) return@coroutineScope

                loadedStatus.fold(
                    onSuccess = { loaded ->
                        ingestStatus(loaded)
                        if (loaded.consentRequired) {
                            conversations = emptyList()
                            if (!isDraftChat) closeConversation()
                        } else {
                            loadedConversations.fold(
                                onSuccess = { values ->
                                    conversations = values.sortedByDescending(::conversationDate)
                                    currentConversation = currentConversation?.let { selected ->
                                        values.firstOrNull { it.id == selected.id } ?: selected
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
                loadedContext.fold(
                    onSuccess = ::ingestContext,
                    onFailure = { contextFailure = failure(it) },
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (isCurrentForegroundOperation(generation)) {
                val mapped = failure(error)
                failure = mapped
                contextFailure = mapped
            }
        } finally {
            if (isCurrentForegroundOperation(generation)) isLoading = false
        }
    }

    suspend fun refreshStatus() {
        if (!isAppForegrounded || isPerformingDestructiveOperation) return
        val generation = foregroundGeneration
        val result = runCatchingSuspend { repository.loadStatus() }
        if (!isCurrentForegroundOperation(generation)) return
        result.onSuccess(::ingestStatus).onFailure { failure = failure(it) }
    }

    suspend fun acceptConsent() {
        if (!isAppForegrounded || isPerformingDestructiveOperation) return
        val generation = foregroundGeneration
        failure = null
        isLoading = true
        try {
            repository.acceptConsent()
            if (!isCurrentForegroundOperation(generation)) return
            val loadedStatus = repository.loadStatus()
            if (!isCurrentForegroundOperation(generation)) return
            ingestStatus(loadedStatus)
            if (status?.consentRequired == false) {
                    val schoolScope = contextBuilder?.currentSchoolScope()
                        ?: throw GradeyAIException(
                            GradeyAIErrorKind.NO_CONTEXT,
                            "",
                        )
                if (!isCurrentForegroundOperation(generation)) return
                val loadedConversations = repository.listConversations(schoolScope)
                if (!isCurrentForegroundOperation(generation)) return
                conversations = loadedConversations
                    .sortedByDescending(::conversationDate)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (isCurrentForegroundOperation(generation)) failure = failure(error)
        } finally {
            if (isCurrentForegroundOperation(generation)) isLoading = false
        }
    }

    suspend fun revokeConsent() {
        if (!isAppForegrounded || isPerformingDestructiveOperation) return
        isPerformingDestructiveOperation = true
        cancelOperations()
        failure = null
        isLoading = true
        try {
            repository.revokeConsent()
            cancelOperations()
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
            isPerformingDestructiveOperation = false
        }
    }

    fun beginDraftChat(localizedTitle: String) {
        if (!isAppForegrounded || isPerformingDestructiveOperation) return
        cancelOpen()
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
        if (!isAppForegrounded || isPerformingDestructiveOperation) return
        stop()
        cancelOpen()
        failure = null
        draftConversationID = null
        currentConversation = conversation
        messages = emptyList()
        lastFailedRequest = null
        isOpeningConversation = true
        val token = idProvider()
        activeOpenToken = token
        val operation = scope.launch(start = CoroutineStart.LAZY) {
            try {
                val detail = repository.loadConversation(conversation.id)
                if (activeOpenToken != token) return@launch
                currentConversation = detail.conversation
                messages = detail.messages
                upsert(detail.conversation)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (activeOpenToken == token) failure = failure(error)
            } finally {
                if (activeOpenToken == token) {
                    activeOpenToken = null
                    openJob = null
                    isOpeningConversation = false
                }
            }
        }
        openJob = operation
        operation.start()
        try {
            operation.join()
        } catch (error: CancellationException) {
            // The list subtree leaves composition as soon as the optimistic selection is set.
            // Its awaiting coroutine may be cancelled, but the controller owns this operation;
            // explicit Back/close/disposal cancels it through cancelOpen/cancelOperations.
            throw error
        }
    }

    fun closeConversation() {
        cancelOpen()
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
        if (!isAppForegrounded || isSending || isOpeningConversation ||
            isPerformingDestructiveOperation
        ) return
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

        launchSendOperation { token -> performSend(token, text) }
    }

    suspend fun retry() {
        if (!isAppForegrounded || isSending || isOpeningConversation ||
            isPerformingDestructiveOperation
        ) return
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
        lastFailedRequest = null
        launchSendOperation { token ->
            startStream(token, conversation, failed.text, failed.clientMessageID, context)
        }
    }

    fun canRetry(message: GradeyAIMessage): Boolean {
        val failed = lastFailedRequest ?: return false
        return message.role == GradeyAIMessageRole.ASSISTANT &&
            message.status == GradeyAIMessageStatus.FAILED &&
            currentConversation?.id == failed.conversationID &&
            isAppForegrounded &&
            !isPerformingDestructiveOperation &&
            status?.canSend == true &&
            message.createdAtEpochMillis >= failed.startedAtEpochMillis
    }

    fun stop() = stop(reconcileStatus = true)

    private fun stop(reconcileStatus: Boolean) {
        if (sendJob == null && !isSending) return
        val wasStreaming = isStreaming
        activeSendToken = null
        sendJob?.cancel()
        sendJob = null
        isSending = false
        isStreaming = false
        val streamingMessageIndex = messages.indexOfLast {
            it.role == GradeyAIMessageRole.ASSISTANT && it.status == GradeyAIMessageStatus.STREAMING
        }
        messages = messages.mapIndexed { index, message ->
            if (index == streamingMessageIndex) {
                message.copy(status = GradeyAIMessageStatus.CANCELLED)
            } else {
                message
            }
        }
        lastFailedRequest = null
        if (wasStreaming && reconcileStatus && isAppForegrounded) {
            val generation = foregroundGeneration
            scope.launch {
                delay(750)
                val result = runCatchingSuspend { repository.loadStatus() }
                if (isCurrentForegroundOperation(generation)) result.onSuccess(::ingestStatus)
            }
        }
    }

    fun cancelOperations() {
        cancelOpen()
        stop()
    }

    suspend fun delete(conversation: GradeyAIConversation) {
        if (!isAppForegrounded || isPerformingDestructiveOperation) return
        isPerformingDestructiveOperation = true
        if (currentConversation?.id == conversation.id) {
            cancelOpen()
            stop()
        }
        failure = null
        if (conversation.id == draftConversationID) {
            closeConversation()
            isPerformingDestructiveOperation = false
            return
        }
        try {
            repository.deleteConversation(conversation.id)
            cancelOperations()
            conversations = conversations.filterNot { it.id == conversation.id }
            if (currentConversation?.id == conversation.id) closeConversation()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            failure = failure(error)
        } finally {
            isPerformingDestructiveOperation = false
        }
    }

    suspend fun deleteAll() {
        if (!isAppForegrounded || isPerformingDestructiveOperation) return
        isPerformingDestructiveOperation = true
        cancelOperations()
        failure = null
        try {
            val schoolScope = activeSchoolScope ?: contextBuilder?.currentSchoolScope()
                ?: throw GradeyAIException(GradeyAIErrorKind.NO_CONTEXT, "")
            repository.deleteAllConversations(schoolScope)
            cancelOperations()
            conversations = emptyList()
            messages = emptyList()
            currentConversation = null
            lastFailedRequest = null
            draftConversationID = null
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            failure = failure(error)
        } finally {
            isPerformingDestructiveOperation = false
        }
    }

    suspend fun refreshContext() {
        if (!isAppForegrounded || isRefreshingContext || isPerformingDestructiveOperation) return
        val builder = contextBuilder
        if (builder == null) {
            contextFailure = GradeyAIFailure(GradeyAIErrorKind.NO_CONTEXT)
            return
        }
        val generation = foregroundGeneration
        val token = idProvider()
        activeContextRefreshToken = token
        isRefreshingContext = true
        contextFailure = null
        try {
            val refreshed = builder.refreshContext()
            if (activeContextRefreshToken == token && isCurrentForegroundOperation(generation)) {
                ingestContext(refreshed)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (activeContextRefreshToken == token && isCurrentForegroundOperation(generation)) {
                contextFailure = failure(error)
            }
        } finally {
            if (activeContextRefreshToken == token) {
                activeContextRefreshToken = null
                isRefreshingContext = false
            }
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

    private suspend fun launchSendOperation(block: suspend (String) -> Unit) {
        if (isSending) return
        val token = idProvider()
        activeSendToken = token
        isSending = true
        val operation = scope.launch(start = CoroutineStart.LAZY) {
            try {
                block(token)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (activeSendToken == token) failure = failure(error)
            } finally {
                if (activeSendToken == token) {
                    activeSendToken = null
                    sendJob = null
                    isSending = false
                    isStreaming = false
                }
            }
        }
        sendJob = operation
        operation.start()
        try {
            operation.join()
        } catch (error: CancellationException) {
            // Starter-prompt/composer subtrees can leave composition while this controller-owned
            // operation continues. Explicit Stop/Back/disposal remains the cancellation boundary.
            throw error
        }
    }

    private suspend fun performSend(token: String, text: String) {
        if (contextSnapshot == null) refreshContext()
        if (activeSendToken != token) return
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
            conversation = createForSend(token, title(text))
            if (activeSendToken != token) return
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
        startStream(token, conversation, text, clientMessageID, context)
    }

    private suspend fun createForSend(token: String, title: String?): GradeyAIConversation? {
        return try {
            val schoolScope = activeSchoolScope ?: contextBuilder?.currentSchoolScope()
                ?: throw GradeyAIException(GradeyAIErrorKind.NO_CONTEXT, "")
            val conversation = repository.createConversation(schoolScope, title)
            if (activeSendToken != token) return null
            upsert(conversation)
            currentConversation = conversation
            draftConversationID = null
            conversation
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (activeSendToken == token) failure = failure(error)
            null
        }
    }

    private suspend fun startStream(
        token: String,
        conversation: GradeyAIConversation,
        text: String,
        clientMessageID: String,
        context: GradeyAIContextSnapshot,
    ) {
        if (activeSendToken != token) return
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
                if (activeSendToken != token) return@collect
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
                        lastFailedRequest = if (mapped.retryable) {
                            FailedRequest(
                                conversation.id,
                                clientMessageID,
                                text,
                                startedAt,
                            )
                        } else {
                            null
                        }
                    }
                }
            }
            if (!receivedTerminalEvent && activeSendToken == token) {
                throw GradeyAIException(
                    GradeyAIErrorKind.MALFORMED_RESPONSE,
                    "Gradey AI ended the reply before returning a result.",
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (activeSendToken != token) return
            markAssistantFailed(assistantMessageID, conversation.id, context.generatedAtEpochMillis)
            val mapped = failure(error)
            failure = mapped
            lastFailedRequest = if (mapped.retryable) {
                FailedRequest(
                    conversation.id,
                    clientMessageID,
                    text,
                    startedAt,
                )
            } else {
                null
            }
        } finally {
            if (activeSendToken == token) {
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
        // A partial snapshot is still usable. The UI labels it as incomplete instead of
        // incorrectly claiming that no marks or timetable are available.
        contextFailure = null
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
        cancelOpen()
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

    private fun cancelOpen() {
        activeOpenToken = null
        openJob?.cancel()
        openJob = null
        isOpeningConversation = false
    }

    private fun failure(error: Throwable): GradeyAIFailure = when (error) {
        is GradeyAIException -> GradeyAIFailure(error.kind, retryable = error.retryable)
        is GradeyAIContextException -> GradeyAIFailure(GradeyAIErrorKind.NO_CONTEXT)
        else -> GradeyAIFailure(
            GradeyAIErrorKind.TRANSPORT,
            retryable = true,
        )
    }

    private fun isCurrentForegroundOperation(generation: Int): Boolean =
        isAppForegrounded && foregroundGeneration == generation

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
