package com.bukovinafilip.gradey.feature.gradeyai

import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.bukovinafilip.gradey.domain.GradeyAIContextBuilding
import com.bukovinafilip.gradey.domain.GradeyAIEntryPolicy
import com.bukovinafilip.gradey.domain.GradeyAIEntryState
import com.bukovinafilip.gradey.domain.GradeyAIErrorKind
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.model.GradeyAIConversation
import com.bukovinafilip.gradey.model.GradeyAIMessage
import com.bukovinafilip.gradey.model.GradeyAIMessageRole
import com.bukovinafilip.gradey.model.GradeyAIMessageStatus
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.ui.GradeyAuroraBackground
import com.bukovinafilip.gradey.ui.GradeyIcons
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyPrimaryButton
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.launch

@Composable
fun GradeyAIScreen(
    repository: GradeyAIRepository,
    contextBuilder: GradeyAIContextBuilding? = null,
    isGuestMode: Boolean,
    supportTier: GradeySupportTier = GradeySupportTier.NONE,
    onOpenAccount: () -> Unit,
    onOpenSupport: (() -> Unit)? = null,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val coroutineScope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current
    val controller = remember(repository, contextBuilder) {
        GradeyAIController(
            repository = repository,
            contextBuilder = contextBuilder,
            scope = coroutineScope,
            initiallyForegrounded = GradeyAILifecyclePolicy.isForeground(
                lifecycleOwner.lifecycle.currentState,
            ),
        )
    }
    val entryState = GradeyAIEntryPolicy.resolve(isGuestMode, repository.isConfigured)
    val currentEntryState by rememberUpdatedState(entryState)
    var pendingDeletion by remember { mutableStateOf<GradeyAIConversation?>(null) }
    var dangerousAction by remember { mutableStateOf<DangerousAction?>(null) }

    BackHandler {
        if (controller.currentConversation != null) controller.closeConversation() else onClose()
    }
    DisposableEffect(controller, lifecycleOwner) {
        val lifecycle = lifecycleOwner.lifecycle
        if (GradeyAILifecyclePolicy.isForeground(lifecycle.currentState)) {
            if (controller.onAppForegrounded() && currentEntryState == GradeyAIEntryState.SERVICE) {
                coroutineScope.launch { controller.bootstrap() }
            }
        } else {
            controller.onAppBackgrounded()
        }
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> controller.onAppBackgrounded()
                Lifecycle.Event.ON_START -> {
                    if (controller.onAppForegrounded() && currentEntryState == GradeyAIEntryState.SERVICE) {
                        coroutineScope.launch { controller.bootstrap() }
                    }
                }
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            controller.onAppBackgrounded()
        }
    }
    LaunchedEffect(controller, supportTier) { controller.applySupportTier(supportTier) }
    LaunchedEffect(controller, entryState) {
        if (entryState == GradeyAIEntryState.SERVICE) controller.bootstrap()
    }

    Surface(
        modifier = modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background,
    ) {
        Box(Modifier.fillMaxSize()) {
            GradeyAuroraBackground()
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .safeDrawingPadding(),
            ) {
                when (entryState) {
                    GradeyAIEntryState.SIGN_IN_REQUIRED -> GradeyAIStaticPage(onClose) {
                        GradeyAIUnavailableCard(
                            title = stringResource(R.string.gradey_ai_sign_in_title),
                            message = stringResource(R.string.gradey_ai_sign_in_message),
                            action = stringResource(R.string.gradey_ai_open_account),
                            onAction = onOpenAccount,
                        )
                    }
                    GradeyAIEntryState.NOT_CONFIGURED -> GradeyAIStaticPage(onClose) {
                        GradeyAIUnavailableCard(
                            title = stringResource(R.string.gradey_ai_not_configured_title),
                            message = stringResource(R.string.gradey_ai_not_configured_message),
                        )
                    }
                    GradeyAIEntryState.SERVICE -> GradeyAIServiceContent(
                        controller = controller,
                        supportTier = supportTier,
                        onOpenSupport = onOpenSupport,
                        onClose = onClose,
                        onDelete = { pendingDeletion = it },
                        onDeleteAll = { dangerousAction = DangerousAction.DELETE_ALL },
                        onRevoke = { dangerousAction = DangerousAction.REVOKE },
                    )
                }
            }
        }
    }

    pendingDeletion?.let { conversation ->
        AlertDialog(
            onDismissRequest = { pendingDeletion = null },
            title = { Text(stringResource(R.string.gradey_ai_delete_chat_title)) },
            text = { Text(stringResource(R.string.gradey_ai_delete_chat_message)) },
            confirmButton = {
                TextButton(onClick = {
                    pendingDeletion = null
                    coroutineScope.launch { controller.delete(conversation) }
                }) {
                    Text(
                        stringResource(R.string.gradey_ai_delete_chat_action),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDeletion = null }) {
                    Text(stringResource(R.string.gradey_ai_cancel))
                }
            },
        )
    }

    dangerousAction?.let { action ->
        val isDeleteAll = action == DangerousAction.DELETE_ALL
        AlertDialog(
            onDismissRequest = { dangerousAction = null },
            title = {
                Text(
                    stringResource(
                        if (isDeleteAll) R.string.gradey_ai_delete_all_title else R.string.gradey_ai_revoke_title,
                    ),
                )
            },
            text = {
                Text(
                    stringResource(
                        if (isDeleteAll) R.string.gradey_ai_delete_all_message else R.string.gradey_ai_revoke_message,
                    ),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    dangerousAction = null
                    coroutineScope.launch {
                        if (isDeleteAll) controller.deleteAll() else controller.revokeConsent()
                    }
                }) {
                    Text(
                        stringResource(
                            if (isDeleteAll) R.string.gradey_ai_delete_all_action else R.string.gradey_ai_revoke_action,
                        ),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { dangerousAction = null }) {
                    Text(stringResource(R.string.gradey_ai_cancel))
                }
            },
        )
    }
}

private enum class DangerousAction { DELETE_ALL, REVOKE }

@Composable
private fun GradeyAIServiceContent(
    controller: GradeyAIController,
    supportTier: GradeySupportTier,
    onOpenSupport: (() -> Unit)?,
    onClose: () -> Unit,
    onDelete: (GradeyAIConversation) -> Unit,
    onDeleteAll: () -> Unit,
    onRevoke: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize()) {
        GradeyAITopBar(
            title = controller.currentConversation?.title ?: stringResource(R.string.gradey_ai_title),
            showBack = controller.currentConversation != null,
            showOptions = controller.hasConsent,
            optionsEnabled = !controller.isSending && !controller.isPerformingDestructiveOperation,
            hasConversations = controller.conversations.isNotEmpty(),
            onBack = controller::closeConversation,
            onClose = onClose,
            onDeleteCurrent = { controller.currentConversation?.let(onDelete) },
            onDeleteAll = onDeleteAll,
            onRevoke = onRevoke,
        )
        controller.failure?.let { failure ->
            GradeyAIInlineError(
                message = failureText(failure),
                onDismiss = controller::clearFailure,
            )
        }
        when {
            controller.isLoading && controller.status == null -> GradeyAILoading(Modifier.weight(1f))
            controller.status == null -> GradeyAIUnavailable(
                message = controller.failure?.let { failureText(it) }
                    ?: stringResource(R.string.gradey_ai_load_failed_message),
                onRetry = { scope.launch { controller.bootstrap() } },
                modifier = Modifier.weight(1f),
            )
            controller.status?.consentRequired == true -> GradeyAIConsentContent(
                isServiceEnabled = controller.status?.enabled == true,
                isLoading = controller.isLoading,
                onAccept = { scope.launch { controller.acceptConsent() } },
                modifier = Modifier.weight(1f),
            )
            controller.currentConversation == null -> GradeyAIConversationList(
                controller = controller,
                supportTier = supportTier,
                onOpenSupport = onOpenSupport,
                onDelete = onDelete,
                modifier = Modifier.weight(1f),
            )
            else -> GradeyAIChat(
                controller = controller,
                supportTier = supportTier,
                onOpenSupport = onOpenSupport,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun GradeyAITopBar(
    title: String,
    showBack: Boolean,
    showOptions: Boolean,
    optionsEnabled: Boolean,
    hasConversations: Boolean,
    onBack: () -> Unit,
    onClose: () -> Unit,
    onDeleteCurrent: () -> Unit,
    onDeleteAll: () -> Unit,
    onRevoke: () -> Unit,
) {
    var menuExpanded by remember { mutableStateOf(false) }
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.94f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = GradeySpacing.sm, vertical = GradeySpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (showBack) {
                IconButton(onClick = onBack) {
                    Icon(GradeyIcons.ArrowLeft, contentDescription = stringResource(R.string.gradey_ai_back))
                }
            } else {
                Spacer(Modifier.size(48.dp))
            }
            Text(
                title,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (showOptions) {
                Box {
                    IconButton(enabled = optionsEnabled, onClick = { menuExpanded = true }) {
                        Icon(GradeyIcons.MoreVertical, contentDescription = stringResource(R.string.gradey_ai_options))
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        if (showBack) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.gradey_ai_delete_chat_action)) },
                                leadingIcon = { Icon(GradeyIcons.Delete, contentDescription = null) },
                                onClick = { menuExpanded = false; onDeleteCurrent() },
                            )
                        }
                        DropdownMenuItem(
                            enabled = hasConversations,
                            text = { Text(stringResource(R.string.gradey_ai_delete_all_action)) },
                            leadingIcon = { Icon(GradeyIcons.Delete, contentDescription = null) },
                            onClick = { menuExpanded = false; onDeleteAll() },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.gradey_ai_revoke_action)) },
                            leadingIcon = { Icon(GradeyIcons.SecurityLock, contentDescription = null) },
                            onClick = { menuExpanded = false; onRevoke() },
                        )
                    }
                }
            } else {
                IconButton(onClick = onClose) {
                    Icon(GradeyIcons.Cancel, contentDescription = stringResource(R.string.gradey_ai_close))
                }
            }
        }
    }
}

@Composable
private fun GradeyAIConversationList(
    controller: GradeyAIController,
    supportTier: GradeySupportTier,
    onOpenSupport: (() -> Unit)?,
    onDelete: (GradeyAIConversation) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(GradeySpacing.lg),
        verticalArrangement = Arrangement.spacedBy(GradeySpacing.md),
    ) {
        item {
            GradeyHero(
                title = stringResource(R.string.gradey_ai_welcome_title),
                subtitle = stringResource(R.string.gradey_ai_welcome_message),
            )
        }
        if (controller.status?.enabled == false) item { GradeyAIAvailabilityBanner() }
        item {
            GradeyAILimitCard(
                controller = controller,
                supportTier = supportTier,
                onOpenSupport = onOpenSupport,
                showNewChat = true,
            )
        }
        item { GradeyAIContextCard(controller) }
        if (controller.conversations.isEmpty()) {
            item {
                GradeySectionCard(title = stringResource(R.string.gradey_ai_empty_title)) {
                    Text(
                        stringResource(R.string.gradey_ai_empty_message),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    GradeyAIStarterPrompts(controller)
                }
            }
        } else {
            item {
                Text(
                    stringResource(R.string.gradey_ai_chats_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
            }
            items(controller.conversations, key = GradeyAIConversation::id) { conversation ->
                GradeySectionCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(
                            enabled = !controller.isPerformingDestructiveOperation,
                            onClick = { scope.launch { controller.open(conversation) } },
                        ),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(GradeySpacing.md),
                    ) {
                        Surface(
                            modifier = Modifier.size(40.dp),
                            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f),
                            shape = MaterialTheme.shapes.small,
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    GradeyIcons.Message,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                        Column(Modifier.weight(1f)) {
                            Text(
                                conversation.title.ifBlank { stringResource(R.string.gradey_ai_new_chat) },
                                fontWeight = FontWeight.Bold,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                relativeConversationTime(conversation),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        IconButton(
                            enabled = !controller.isPerformingDestructiveOperation,
                            onClick = { onDelete(conversation) },
                        ) {
                            Icon(
                                GradeyIcons.Delete,
                                contentDescription = stringResource(R.string.gradey_ai_delete_chat_action),
                            )
                        }
                    }
                }
            }
        }
        item { GradeyAIPrivacyFootnote() }
    }
}

@Composable
private fun GradeyAIChat(
    controller: GradeyAIController,
    supportTier: GradeySupportTier,
    onOpenSupport: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    Column(modifier.fillMaxWidth().imePadding()) {
        if (controller.status?.enabled == false) GradeyAIAvailabilityBanner(
            Modifier.padding(horizontal = GradeySpacing.lg),
        )
        GradeyAIContextCard(controller, Modifier.padding(horizontal = GradeySpacing.lg))
        val listState = rememberLazyListState()
        val lastContent = controller.messages.lastOrNull()?.content
        LaunchedEffect(controller.messages.size, lastContent) {
            if (controller.messages.isNotEmpty()) listState.animateScrollToItem(controller.messages.lastIndex)
        }
        when {
            controller.isOpeningConversation && controller.messages.isEmpty() -> {
                GradeyAILoading(Modifier.weight(1f))
            }
            controller.messages.isEmpty() -> {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(GradeySpacing.lg),
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        stringResource(R.string.gradey_ai_chat_empty_title),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        stringResource(R.string.gradey_ai_chat_empty_message),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(GradeySpacing.md))
                    GradeyAIStarterPrompts(controller)
                }
            }
            else -> LazyColumn(
                modifier = Modifier.weight(1f),
                state = listState,
                contentPadding = PaddingValues(GradeySpacing.lg),
                verticalArrangement = Arrangement.spacedBy(GradeySpacing.md),
            ) {
                items(controller.messages, key = GradeyAIMessage::id) { message ->
                    GradeyAIMessageBubble(
                        message = message,
                        canRetry = controller.canRetry(message),
                        onRetry = { scope.launch { controller.retry() } },
                    )
                }
            }
        }
        GradeyAIComposer(controller)
        if ((controller.status?.remaining ?: 1) == 0 && supportTier != GradeySupportTier.PLUS) {
            GradeyAISupportUpgrade(onOpenSupport, Modifier.padding(horizontal = GradeySpacing.lg))
        }
    }
}

@Composable
private fun GradeyAIComposer(controller: GradeyAIController) {
    val scope = rememberCoroutineScope()
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                start = GradeySpacing.lg,
                top = GradeySpacing.sm,
                end = GradeySpacing.lg,
                bottom = GradeySpacing.md,
            ),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = MaterialTheme.shapes.large,
        border = BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
        ),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = GradeySpacing.md, vertical = GradeySpacing.sm),
            verticalArrangement = Arrangement.spacedBy(GradeySpacing.xs),
        ) {
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm),
            ) {
                OutlinedTextField(
                    value = controller.draft,
                    onValueChange = { controller.draft = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text(stringResource(R.string.gradey_ai_composer_placeholder)) },
                    minLines = 1,
                    maxLines = 4,
                )
                IconButton(
                    enabled = controller.isSending || controller.canSend,
                    onClick = {
                        if (controller.isSending) controller.stop() else scope.launch { controller.send() }
                    },
                ) {
                    Icon(
                        if (controller.isSending) GradeyIcons.Stop else GradeyIcons.ArrowUp,
                        contentDescription = stringResource(
                            if (controller.isSending) R.string.gradey_ai_stop else R.string.gradey_ai_send,
                        ),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                GradeyAILimitText(controller)
                if (controller.draft.length > 1_800) {
                    Text(
                        "${controller.draft.length}/2000",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (controller.draft.length > 2_000) {
                            MaterialTheme.colorScheme.error
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun GradeyAIMessageBubble(
    message: GradeyAIMessage,
    canRetry: Boolean,
    onRetry: () -> Unit,
) {
    Row(Modifier.fillMaxWidth()) {
        if (message.role == GradeyAIMessageRole.USER) Spacer(Modifier.weight(1f))
        if (message.role == GradeyAIMessageRole.ASSISTANT) {
            Icon(
                GradeyIcons.Sparkles,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(top = GradeySpacing.sm, end = GradeySpacing.sm),
            )
        }
        Surface(
            modifier = Modifier.widthIn(max = 560.dp),
            color = if (message.role == GradeyAIMessageRole.USER) {
                MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)
            } else {
                MaterialTheme.colorScheme.surfaceContainer
            },
            shape = MaterialTheme.shapes.medium,
            border = BorderStroke(
                1.dp,
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f),
            ),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = GradeySpacing.md, vertical = GradeySpacing.sm),
                verticalArrangement = Arrangement.spacedBy(GradeySpacing.xs),
            ) {
                if (message.role == GradeyAIMessageRole.ASSISTANT && message.content.isNotEmpty()) {
                    Text(
                        stringResource(R.string.gradey_ai_generated),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                when {
                    message.content.isEmpty() && message.status == GradeyAIMessageStatus.STREAMING -> {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    }
                    message.role == GradeyAIMessageRole.ASSISTANT &&
                        message.status == GradeyAIMessageStatus.COMPLETE -> {
                        GradeyAIMarkdownText(message.content)
                    }
                    else -> Text(message.content)
                }
                when (message.status) {
                    GradeyAIMessageStatus.FAILED -> if (canRetry) {
                        TextButton(onClick = onRetry) {
                            Icon(GradeyIcons.Refresh, contentDescription = null)
                            Text(stringResource(R.string.gradey_ai_retry))
                        }
                    }
                    GradeyAIMessageStatus.CANCELLED -> Text(
                        stringResource(R.string.gradey_ai_response_cancelled),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    else -> Unit
                }
            }
        }
        if (message.role == GradeyAIMessageRole.ASSISTANT) Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun GradeyAIStarterPrompts(controller: GradeyAIController) {
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
        controller.starterPrompts().forEach { prompt ->
            val text = when (prompt.kind) {
                GradeyAIStarterPromptKind.IMPROVE_SUBJECT -> stringResource(
                    R.string.gradey_ai_prompt_improve,
                    prompt.subject.orEmpty(),
                )
                GradeyAIStarterPromptKind.PREPARE_SUBJECT -> stringResource(
                    R.string.gradey_ai_prompt_prepare,
                    prompt.subject.orEmpty(),
                )
                GradeyAIStarterPromptKind.SUMMARIZE_MARKS -> stringResource(
                    R.string.gradey_ai_prompt_summarize,
                )
                GradeyAIStarterPromptKind.UPCOMING_TIMETABLE -> stringResource(
                    R.string.gradey_ai_prompt_timetable,
                )
            }
            OutlinedButton(
                modifier = Modifier.fillMaxWidth(),
                enabled = !controller.isSending &&
                    !controller.isPerformingDestructiveOperation &&
                    controller.status?.canSend == true,
                onClick = { scope.launch { controller.send(text) } },
            ) {
                Icon(GradeyIcons.Sparkles, contentDescription = null)
                Spacer(Modifier.size(GradeySpacing.sm))
                Text(text, modifier = Modifier.weight(1f), textAlign = TextAlign.Start)
            }
        }
    }
}

@Composable
private fun GradeyAIContextCard(controller: GradeyAIController, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val snapshot = controller.contextSnapshot
    val title = when {
        controller.isRefreshingContext -> stringResource(R.string.gradey_ai_context_refreshing)
        snapshot == null -> stringResource(R.string.gradey_ai_context_unavailable)
        snapshot.isPartial || snapshot.isStale -> stringResource(R.string.gradey_ai_context_partial)
        else -> stringResource(R.string.gradey_ai_context_ready)
    }
    GradeySectionCard(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm),
        ) {
            Icon(
                if (snapshot == null) GradeyIcons.ErrorCircle else GradeyIcons.CheckCircle,
                contentDescription = null,
                tint = if (snapshot == null || snapshot.isPartial) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.primary
                },
            )
            Column(Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodySmall)
                val contextFailure = controller.contextFailure
                if (contextFailure != null) {
                    Text(
                        failureText(contextFailure),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                } else if (snapshot != null) {
                    Text(
                        relativeTime(snapshot.generatedAtEpochMillis),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            IconButton(
                enabled = !controller.isRefreshingContext && !controller.isSending,
                onClick = { scope.launch { controller.refreshContext() } },
            ) {
                if (controller.isRefreshingContext) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Icon(GradeyIcons.Refresh, contentDescription = stringResource(R.string.gradey_ai_context_refresh))
                }
            }
        }
    }
}

@Composable
private fun GradeyAILimitCard(
    controller: GradeyAIController,
    supportTier: GradeySupportTier,
    onOpenSupport: (() -> Unit)?,
    showNewChat: Boolean,
) {
    val newChatTitle = stringResource(R.string.gradey_ai_new_chat)
    GradeySectionCard(title = stringResource(R.string.gradey_ai_daily_limit)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            GradeyAILimitText(controller, Modifier.weight(1f))
            if (showNewChat) {
                Button(
                    enabled = controller.canStartNewChat,
                    onClick = { controller.beginDraftChat(newChatTitle) },
                ) {
                    Icon(GradeyIcons.Edit, contentDescription = null)
                    Text(stringResource(R.string.gradey_ai_new_chat))
                }
            }
        }
        if ((controller.status?.remaining ?: 1) == 0 && supportTier != GradeySupportTier.PLUS) {
            GradeyAISupportUpgrade(onOpenSupport)
        }
    }
}

@Composable
private fun GradeyAILimitText(controller: GradeyAIController, modifier: Modifier = Modifier) {
    val status = controller.status ?: return
    Column(modifier) {
        Text(
            stringResource(R.string.gradey_ai_remaining, status.remaining, status.dailyLimit),
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.bodySmall,
        )
        status.resetAtEpochMillis?.let { resetAt ->
            Text(
                stringResource(R.string.gradey_ai_resets, formattedResetTime(resetAt)),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun GradeyAISupportUpgrade(
    onOpenSupport: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .then(if (onOpenSupport != null) Modifier.clickable(onClick = onOpenSupport) else Modifier),
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
        shape = MaterialTheme.shapes.small,
    ) {
        Row(
            modifier = Modifier.padding(GradeySpacing.sm),
            horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm),
        ) {
            Icon(
                GradeyIcons.Sparkles,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
            Column {
                Text(stringResource(R.string.gradey_ai_upgrade_message), fontWeight = FontWeight.SemiBold)
                Text(
                    if (onOpenSupport != null) {
                        stringResource(R.string.gradey_ai_upgrade_action)
                    } else {
                        stringResource(R.string.gradey_ai_upgrade_account_hint)
                    },
                    color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

@Composable
private fun GradeyAIAvailabilityBanner(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.errorContainer,
        shape = MaterialTheme.shapes.small,
    ) {
        Row(
            modifier = Modifier.padding(GradeySpacing.md),
            horizontalArrangement = Arrangement.spacedBy(GradeySpacing.md),
        ) {
            Icon(GradeyIcons.PauseCircle, contentDescription = null)
            Column {
                Text(stringResource(R.string.gradey_ai_paused_title), fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.gradey_ai_paused_message), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun GradeyAIConsentContent(
    isServiceEnabled: Boolean,
    isLoading: Boolean,
    onAccept: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(GradeySpacing.lg),
        verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg),
    ) {
        item {
            GradeyHero(
                title = stringResource(R.string.gradey_ai_consent_title),
                subtitle = stringResource(R.string.gradey_ai_consent_subtitle),
            )
        }
        if (!isServiceEnabled) item { GradeyAIAvailabilityBanner() }
        item {
            ConsentDetail(
                GradeyIcons.Sparkles,
                stringResource(R.string.gradey_ai_consent_system_title),
                stringResource(R.string.gradey_ai_consent_system_message),
            )
        }
        item {
            ConsentDetail(
                GradeyIcons.Analytics,
                stringResource(R.string.gradey_ai_consent_school_title),
                stringResource(R.string.gradey_ai_consent_school_message),
            )
        }
        item {
            ConsentDetail(
                GradeyIcons.Cloud,
                stringResource(R.string.gradey_ai_consent_azure_title),
                stringResource(R.string.gradey_ai_consent_azure_message),
            )
        }
        item {
            ConsentDetail(
                GradeyIcons.History,
                stringResource(R.string.gradey_ai_consent_control_title),
                stringResource(R.string.gradey_ai_consent_control_message),
            )
        }
        item {
            Text(
                stringResource(R.string.gradey_ai_disclaimer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        item {
            GradeyPrimaryButton(
                onClick = onAccept,
                enabled = !isLoading,
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp,
                    )
                    Spacer(Modifier.size(GradeySpacing.sm))
                }
                Text(stringResource(R.string.gradey_ai_consent_action))
            }
        }
    }
}

@Composable
private fun ConsentDetail(icon: ImageVector, title: String, message: String) {
    GradeySectionCard {
        Row(horizontalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Column {
                Text(title, fontWeight = FontWeight.Bold)
                Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun GradeyAIPrivacyFootnote() {
    Row(horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
        Icon(
            GradeyIcons.SecurityLock,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(
            stringResource(R.string.gradey_ai_privacy_footnote),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun GradeyAIInlineError(message: String, onDismiss: () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = GradeySpacing.lg, vertical = GradeySpacing.xs),
        color = MaterialTheme.colorScheme.errorContainer,
        shape = MaterialTheme.shapes.small,
    ) {
        Row(
            modifier = Modifier.padding(GradeySpacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(GradeyIcons.ErrorCircle, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Text(message, modifier = Modifier.weight(1f).padding(horizontal = GradeySpacing.sm))
            IconButton(onClick = onDismiss) {
                Icon(GradeyIcons.Cancel, contentDescription = stringResource(R.string.gradey_ai_close_error))
            }
        }
    }
}

@Composable
private fun GradeyAIStaticPage(onClose: () -> Unit, content: @Composable () -> Unit) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(GradeySpacing.lg),
        verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg),
    ) {
        item {
            Box(Modifier.fillMaxWidth()) {
                Text(
                    stringResource(R.string.gradey_ai_title),
                    modifier = Modifier.align(Alignment.Center),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                )
                IconButton(modifier = Modifier.align(Alignment.CenterEnd), onClick = onClose) {
                    Icon(GradeyIcons.Cancel, contentDescription = stringResource(R.string.gradey_ai_close))
                }
            }
        }
        item { content() }
    }
}

@Composable
private fun GradeyAILoading(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(GradeySpacing.md))
        Text(stringResource(R.string.gradey_ai_loading), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun GradeyAIUnavailable(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(GradeySpacing.lg),
        verticalArrangement = Arrangement.Center,
    ) {
        GradeyAIUnavailableCard(
            title = stringResource(R.string.gradey_ai_load_failed_title),
            message = message,
            action = stringResource(R.string.gradey_ai_retry),
            onAction = onRetry,
        )
    }
}

@Composable
private fun GradeyAIUnavailableCard(
    title: String,
    message: String,
    action: String? = null,
    onAction: (() -> Unit)? = null,
) {
    GradeySectionCard {
        Icon(
            GradeyIcons.Sparkles,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(36.dp),
        )
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (action != null && onAction != null) Button(onClick = onAction) { Text(action) }
    }
}

@Composable
private fun failureText(failure: GradeyAIFailure): String =
    stringResource(failureMessageResource(failure.kind))

internal fun failureMessageResource(kind: GradeyAIErrorKind): Int = when (kind) {
    GradeyAIErrorKind.NOT_CONFIGURED -> R.string.gradey_ai_not_configured_message
    GradeyAIErrorKind.INVALID_PROMPT -> R.string.gradey_ai_error_invalid_prompt
    GradeyAIErrorKind.REQUEST_TOO_LARGE -> R.string.gradey_ai_error_request_too_large
    GradeyAIErrorKind.UNAUTHENTICATED -> R.string.gradey_ai_error_unauthenticated
    GradeyAIErrorKind.NO_CONTEXT -> R.string.gradey_ai_error_no_context
    GradeyAIErrorKind.LIMIT_REACHED -> R.string.gradey_ai_limit_reached
    GradeyAIErrorKind.TRANSPORT -> R.string.gradey_ai_load_failed_message
    GradeyAIErrorKind.MALFORMED_RESPONSE -> R.string.gradey_ai_error_invalid_response
    GradeyAIErrorKind.SERVER -> R.string.gradey_ai_unavailable_message
}

private fun relativeConversationTime(conversation: GradeyAIConversation): String {
    val timestamp = conversation.lastMessageAtEpochMillis ?: conversation.updatedAtEpochMillis
    return relativeTime(timestamp)
}

private fun relativeTime(timestamp: Long): String = DateUtils.getRelativeTimeSpanString(
        timestamp,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
        DateUtils.FORMAT_ABBREV_RELATIVE,
    ).toString()

private fun formattedResetTime(epochMillis: Long): String = DateTimeFormatter
    .ofLocalizedTime(FormatStyle.SHORT)
    .withLocale(Locale.getDefault())
    .format(Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()))
