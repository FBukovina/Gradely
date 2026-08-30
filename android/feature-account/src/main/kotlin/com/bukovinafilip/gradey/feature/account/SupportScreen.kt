package com.bukovinafilip.gradey.feature.account

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.SupportBillingInterval
import com.bukovinafilip.gradey.model.SupportCatalog
import com.bukovinafilip.gradey.model.SupportPlanOption
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing
import com.bukovinafilip.gradey.ui.MetadataRow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

@Composable
fun SupportScreen(
    catalog: SupportCatalog?,
    isSignedIn: Boolean,
    isConfigured: Boolean,
    isLoading: Boolean,
    purchasingOptionID: String?,
    isRestoring: Boolean,
    message: String?,
    appVersion: String,
    appBuild: String,
    onBack: () -> Unit,
    onReload: () -> Unit,
    onPurchasePlan: (SupportPlanOption) -> Unit,
    onPurchaseTip: (String) -> Unit,
    onRestore: () -> Unit,
    onManageSubscription: () -> Unit,
    onOpenHelpCenter: () -> Unit,
    onEmailDeveloper: () -> Unit,
    onOpenGitHub: () -> Unit,
    onOpenPrivacyPolicy: () -> Unit,
    onOpenTermsOfUse: () -> Unit,
    onOpenOpenSide: () -> Unit,
    onEmailGraphics: () -> Unit,
    onClearCache: () -> Unit,
    onRestartOnboarding: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedInterval by remember { mutableStateOf(SupportBillingInterval.MONTHLY) }
    var showCredits by remember { mutableStateOf(false) }
    var versionTapCount by remember { mutableIntStateOf(0) }
    var debugUnlocked by remember { mutableStateOf(false) }

    BackHandler(onBack = onBack)
    LaunchedEffect(Unit) { onReload() }

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
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.support_back),
                        )
                    }
                    Text(
                        stringResource(R.string.support_title),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
            item {
                GradeyHero(
                    stringResource(R.string.support_heading),
                    stringResource(R.string.support_message),
                )
            }

            when {
                isLoading && catalog == null -> item {
                    GradeySectionCard {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(GradeySpacing.md),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator()
                            Text(stringResource(R.string.support_loading))
                        }
                    }
                }

                catalog == null -> item {
                    GradeySectionCard(title = stringResource(R.string.support_unavailable_title)) {
                        Text(
                            if (isConfigured) {
                                message ?: stringResource(R.string.support_unavailable_message)
                            } else {
                                stringResource(R.string.support_not_configured)
                            },
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Button(onClick = onReload, enabled = !isLoading) {
                            Text(stringResource(R.string.support_retry))
                        }
                    }
                }

                else -> {
                    val loadedCatalog = catalog
                    if (loadedCatalog.entitlement.tier != GradeySupportTier.NONE) {
                        item {
                            ActiveSupportCard(
                                catalog = loadedCatalog,
                                onManageSubscription = onManageSubscription,
                            )
                        }
                    }

                    if (loadedCatalog.plans.isNotEmpty()) {
                        item {
                            GradeySectionCard(title = stringResource(R.string.support_plans_title)) {
                                if (!isSignedIn) {
                                    Text(
                                        stringResource(R.string.support_sign_in_required),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
                                    SupportBillingInterval.entries.forEach { interval ->
                                        FilterChip(
                                            selected = selectedInterval == interval,
                                            onClick = { selectedInterval = interval },
                                            label = {
                                                Text(
                                                    stringResource(
                                                        if (interval == SupportBillingInterval.MONTHLY) {
                                                            R.string.support_monthly
                                                        } else {
                                                            R.string.support_yearly
                                                        },
                                                    ),
                                                )
                                            },
                                        )
                                    }
                                }
                                if (selectedInterval == SupportBillingInterval.YEARLY) {
                                    Text(
                                        stringResource(R.string.support_yearly_savings),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                loadedCatalog.plans
                                    .filter { it.interval == selectedInterval }
                                    .sortedBy { it.tier.ordinal }
                                    .forEach { plan ->
                                        SupportPlanButton(
                                            plan = plan,
                                            catalog = loadedCatalog,
                                            isSignedIn = isSignedIn,
                                            isBusy = purchasingOptionID != null || isRestoring,
                                            isPurchasing = purchasingOptionID == plan.id,
                                            onPurchase = { onPurchasePlan(plan) },
                                        )
                                    }
                            }
                        }
                    }

                    if (loadedCatalog.tips.isNotEmpty()) {
                        item {
                            GradeySectionCard(title = stringResource(R.string.support_tips_title)) {
                                Text(
                                    stringResource(R.string.support_tips_message),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                loadedCatalog.tips.forEach { tip ->
                                    OutlinedButton(
                                        onClick = { onPurchaseTip(tip.id) },
                                        modifier = Modifier.fillMaxWidth(),
                                        enabled = purchasingOptionID == null && !isRestoring,
                                    ) {
                                        if (purchasingOptionID == tip.id) {
                                            CircularProgressIndicator(
                                                modifier = Modifier.padding(end = GradeySpacing.sm),
                                            )
                                        }
                                        Text("${tip.title} · ${tip.localizedPrice}")
                                    }
                                }
                            }
                        }
                    }

                    item {
                        GradeySectionCard {
                            Button(
                                onClick = onRestore,
                                modifier = Modifier.fillMaxWidth(),
                                enabled = isSignedIn && purchasingOptionID == null && !isRestoring,
                            ) {
                                if (isRestoring) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.padding(end = GradeySpacing.sm),
                                    )
                                }
                                Text(stringResource(R.string.support_restore))
                            }
                            if (loadedCatalog.plans.isNotEmpty()) {
                                Text(
                                    stringResource(R.string.support_renewal_legal),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
                                TextButton(onClick = onOpenPrivacyPolicy) {
                                    Text(stringResource(R.string.privacy_policy))
                                }
                                TextButton(onClick = onOpenTermsOfUse) {
                                    Text(stringResource(R.string.terms_of_use))
                                }
                            }
                            if (!message.isNullOrBlank()) {
                                Text(message, color = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                }
            }

            item {
                GradeySectionCard(title = stringResource(R.string.support_and_about)) {
                    OutlinedButton(onClick = onOpenHelpCenter, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.support_help_center))
                    }
                    OutlinedButton(onClick = onEmailDeveloper, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.support_contact_email))
                    }
                    OutlinedButton(onClick = onOpenGitHub, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.support_github))
                    }
                    OutlinedButton(onClick = { showCredits = true }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.support_credits))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
                        TextButton(onClick = onOpenPrivacyPolicy) {
                            Text(stringResource(R.string.privacy_policy))
                        }
                        TextButton(onClick = onOpenTermsOfUse) {
                            Text(stringResource(R.string.terms_of_use))
                        }
                    }
                    TextButton(
                        onClick = {
                            versionTapCount += 1
                            if (versionTapCount >= DEBUG_UNLOCK_TAPS) debugUnlocked = true
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        MetadataRow(stringResource(R.string.support_version), appVersion)
                    }
                    MetadataRow(stringResource(R.string.support_build), appBuild)
                }
            }

            if (debugUnlocked) {
                item {
                    GradeySectionCard(title = stringResource(R.string.support_debug_title)) {
                        Text(
                            stringResource(R.string.support_debug_message),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        OutlinedButton(onClick = onClearCache, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.support_debug_clear_cache))
                        }
                        OutlinedButton(onClick = onRestartOnboarding, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.support_debug_restart_onboarding))
                        }
                    }
                }
            }
        }
    }

    if (showCredits) {
        AlertDialog(
            onDismissRequest = { showCredits = false },
            icon = { Icon(Icons.Default.Info, contentDescription = null) },
            title = { Text(stringResource(R.string.support_credits)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
                    Text(stringResource(R.string.credits_made_by))
                    Text(stringResource(R.string.credits_lead_developer, "Filip Bukovina"))
                    Text(stringResource(R.string.credits_graphics, "Tomáš Vlk"))
                    Text(stringResource(R.string.bakalari_attribution_message))
                    TextButton(onClick = onOpenOpenSide) { Text("openside.tech") }
                    TextButton(onClick = onEmailDeveloper) { Text("filip@openside.tech") }
                    TextButton(onClick = onEmailGraphics) { Text("tom@openside.tech") }
                }
            },
            confirmButton = {
                TextButton(onClick = { showCredits = false }) {
                    Text(stringResource(R.string.support_done))
                }
            },
        )
    }
}

@Composable
private fun ActiveSupportCard(catalog: SupportCatalog, onManageSubscription: () -> Unit) {
    val entitlement = catalog.entitlement
    GradeySectionCard(title = stringResource(R.string.support_active_title)) {
        Icon(Icons.Default.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(
            stringResource(entitlement.tier.titleResource()),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )
        Text(
            entitlement.expirationEpochMillis?.let { expiration ->
                stringResource(
                    if (entitlement.willRenew) R.string.support_renews else R.string.support_active_until,
                    formatSupportDate(expiration),
                )
            } ?: stringResource(R.string.support_active),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(onClick = onManageSubscription) {
            Text(stringResource(R.string.support_manage))
        }
    }
}

@Composable
private fun SupportPlanButton(
    plan: SupportPlanOption,
    catalog: SupportCatalog,
    isSignedIn: Boolean,
    isBusy: Boolean,
    isPurchasing: Boolean,
    onPurchase: () -> Unit,
) {
    val current = catalog.entitlement
    val isCurrent = current.tier == plan.tier && current.interval == plan.interval
    val isDowngrade = current.tier.ordinal > plan.tier.ordinal
    OutlinedButton(
        onClick = onPurchase,
        modifier = Modifier.fillMaxWidth(),
        enabled = isSignedIn && !isBusy && !isCurrent && !isDowngrade,
    ) {
        Icon(Icons.Default.Favorite, contentDescription = null)
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = GradeySpacing.sm),
        ) {
            Text(stringResource(plan.tier.titleResource()), fontWeight = FontWeight.Bold)
            Text(stringResource(plan.tier.benefitResource()))
            Text(stringResource(R.string.support_ai_per_day, plan.localizedPrice, plan.tier.dailyAILimit))
        }
        when {
            isPurchasing -> CircularProgressIndicator()
            isCurrent -> Text(stringResource(R.string.support_current))
        }
    }
}

private fun GradeySupportTier.titleResource(): Int = when (this) {
    GradeySupportTier.NONE -> R.string.support_free
    GradeySupportTier.STANDARD -> R.string.support_standard
    GradeySupportTier.PLUS -> R.string.support_plus
}

private fun GradeySupportTier.benefitResource(): Int = when (this) {
    GradeySupportTier.NONE -> R.string.support_free_benefit
    GradeySupportTier.STANDARD -> R.string.support_standard_benefit
    GradeySupportTier.PLUS -> R.string.support_plus_benefit
}

private fun formatSupportDate(epochMillis: Long): String = DateTimeFormatter
    .ofLocalizedDate(FormatStyle.MEDIUM)
    .withLocale(Locale.getDefault())
    .format(Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()))

private const val DEBUG_UNLOCK_TAPS = 7
