package com.bukovinafilip.gradey.feature.gradeyai

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.domain.GradeyAIEntryPolicy
import com.bukovinafilip.gradey.domain.GradeyAIEntryState
import com.bukovinafilip.gradey.model.GradeyAIIdentityTier
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.bukovinafilip.gradey.ui.GradeyColors
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun GradeyAIScreen(
    repository: GradeyAIRepository,
    isGuestMode: Boolean,
    onOpenAccount: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var status by remember { mutableStateOf<GradeyAIStatus?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var hasLoadError by remember { mutableStateOf(false) }
    var reloadKey by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val entryState = GradeyAIEntryPolicy.resolve(isGuestMode, repository.isConfigured)

    BackHandler(onBack = onClose)

    LaunchedEffect(repository, entryState, reloadKey) {
        if (entryState != GradeyAIEntryState.SERVICE) return@LaunchedEffect
        isLoading = true
        hasLoadError = false
        try {
            status = repository.loadStatus()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            hasLoadError = true
        } finally {
            isLoading = false
        }
    }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = GradeySpacing.lg,
                top = GradeySpacing.lg,
                end = GradeySpacing.lg,
                bottom = GradeySpacing.xxl,
            ),
            verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg),
        ) {
            item { GradeyAITopBar(onClose) }
            if (hasLoadError && status != null) {
                item {
                    GradeyAIInlineError(onRetry = { reloadKey += 1 })
                }
            }
            when {
                entryState == GradeyAIEntryState.SIGN_IN_REQUIRED -> item {
                    GradeyAIUnavailableCard(
                        title = stringResource(R.string.gradey_ai_sign_in_title),
                        message = stringResource(R.string.gradey_ai_sign_in_message),
                        action = stringResource(R.string.gradey_ai_open_account),
                        onAction = onOpenAccount,
                    )
                }

                entryState == GradeyAIEntryState.NOT_CONFIGURED -> item {
                    GradeyAIUnavailableCard(
                        title = stringResource(R.string.gradey_ai_not_configured_title),
                        message = stringResource(R.string.gradey_ai_not_configured_message),
                    )
                }

                isLoading && status == null -> item { GradeyAILoading() }

                hasLoadError && status == null -> item {
                    GradeyAIUnavailableCard(
                        title = stringResource(R.string.gradey_ai_load_failed_title),
                        message = stringResource(R.string.gradey_ai_load_failed_message),
                        action = stringResource(R.string.gradey_ai_retry),
                        onAction = { reloadKey += 1 },
                    )
                }

                status?.consentRequired == true -> item {
                    GradeyAIConsentContent(
                        isServiceEnabled = status?.enabled == true,
                        isLoading = isLoading,
                        onAccept = {
                            if (isLoading) return@GradeyAIConsentContent
                            scope.launch {
                                isLoading = true
                                hasLoadError = false
                                try {
                                    repository.acceptConsent()
                                    status = repository.loadStatus()
                                } catch (error: CancellationException) {
                                    throw error
                                } catch (_: Throwable) {
                                    hasLoadError = true
                                } finally {
                                    isLoading = false
                                }
                            }
                        },
                    )
                }

                status != null -> item { GradeyAIStatusContent(status = status!!) }
            }
        }
    }
}

@Composable
private fun GradeyAIInlineError(onRetry: () -> Unit) {
    GradeySectionCard {
        Text(
            text = stringResource(R.string.gradey_ai_load_failed_message),
            color = MaterialTheme.colorScheme.error,
        )
        OutlinedButton(onClick = onRetry) { Text(stringResource(R.string.gradey_ai_retry)) }
    }
}

@Composable
private fun GradeyAITopBar(onClose: () -> Unit) {
    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Text(
            text = stringResource(R.string.gradey_ai_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
        )
        IconButton(modifier = Modifier.align(Alignment.CenterEnd), onClick = onClose) {
            Icon(Icons.Default.Close, contentDescription = stringResource(R.string.gradey_ai_close))
        }
    }
}

@Composable
private fun GradeyAILoading() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 64.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg),
    ) {
        CircularProgressIndicator(color = GradeyColors.Primary)
        Text(
            text = stringResource(R.string.gradey_ai_loading),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
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
            Icons.Default.AutoAwesome,
            contentDescription = null,
            tint = GradeyColors.Primary,
            modifier = Modifier.size(36.dp),
        )
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (action != null && onAction != null) {
            Button(onClick = onAction) { Text(action) }
        }
    }
}

@Composable
private fun GradeyAIConsentContent(
    isServiceEnabled: Boolean,
    isLoading: Boolean,
    onAccept: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg)) {
        GradeyHero(
            title = stringResource(R.string.gradey_ai_consent_title),
            subtitle = stringResource(R.string.gradey_ai_consent_subtitle),
        )
        if (!isServiceEnabled) {
            GradeySectionCard(title = stringResource(R.string.gradey_ai_paused_title)) {
                Text(
                    stringResource(R.string.gradey_ai_paused_message),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        ConsentDetail(
            icon = Icons.Default.AutoAwesome,
            title = stringResource(R.string.gradey_ai_consent_system_title),
            message = stringResource(R.string.gradey_ai_consent_system_message),
        )
        ConsentDetail(
            icon = Icons.Default.BarChart,
            title = stringResource(R.string.gradey_ai_consent_school_title),
            message = stringResource(R.string.gradey_ai_consent_school_message),
        )
        ConsentDetail(
            icon = Icons.Default.Cloud,
            title = stringResource(R.string.gradey_ai_consent_azure_title),
            message = stringResource(R.string.gradey_ai_consent_azure_message),
        )
        ConsentDetail(
            icon = Icons.Default.History,
            title = stringResource(R.string.gradey_ai_consent_control_title),
            message = stringResource(R.string.gradey_ai_consent_control_message),
        )
        Text(
            text = stringResource(R.string.gradey_ai_disclaimer),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodySmall,
        )
        Button(
            modifier = Modifier.fillMaxWidth(),
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

@Composable
private fun ConsentDetail(icon: ImageVector, title: String, message: String) {
    GradeySectionCard {
        Row(horizontalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
            Icon(icon, contentDescription = null, tint = GradeyColors.Primary)
            Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.xs)) {
                Text(title, fontWeight = FontWeight.Bold)
                Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun GradeyAIStatusContent(status: GradeyAIStatus) {
    Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg)) {
        GradeyHero(
            title = stringResource(R.string.gradey_ai_ready_title),
            subtitle = stringResource(R.string.gradey_ai_ready_message),
        )
        if (!status.enabled) {
            GradeySectionCard(title = stringResource(R.string.gradey_ai_paused_title)) {
                Text(
                    stringResource(R.string.gradey_ai_paused_message),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        GradeySectionCard(title = stringResource(R.string.gradey_ai_daily_limit)) {
            Text(
                text = stringResource(
                    R.string.gradey_ai_remaining,
                    status.remaining,
                    status.dailyLimit,
                ),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = stringResource(R.string.gradey_ai_chat_next),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = stringResource(
                    when (status.tier) {
                        GradeyAIIdentityTier.ANONYMOUS -> R.string.gradey_ai_identity_anonymous
                        GradeyAIIdentityTier.LINKED -> R.string.gradey_ai_identity_linked
                    },
                ),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Lock, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.size(GradeySpacing.sm))
            Text(
                text = stringResource(R.string.gradey_ai_disclaimer),
                modifier = Modifier.weight(1f),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Start,
            )
        }
    }
}
