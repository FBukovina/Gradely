package com.bukovinafilip.gradey.feature.account

import android.content.ClipData
import android.content.ClipboardManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.SupportBillingInterval
import com.bukovinafilip.gradey.model.SupportCatalog
import com.bukovinafilip.gradey.model.SupportEntitlement
import com.bukovinafilip.gradey.model.SupportPlanOption
import com.bukovinafilip.gradey.model.SupportPlanEligibility
import com.bukovinafilip.gradey.ui.GradeyIcons
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
    onOpenDeveloperInstagram: () -> Unit,
    gradeyAccountID: String? = null,
    revenueCatAppUserID: String? = null,
    revenueCatOriginalAppUserID: String? = null,
    linkedSchoolAccountID: String? = null,
    isGuestMode: Boolean? = null,
    hasCompletedOnboardingV2: Boolean? = null,
    onboardingProgress: String? = null,
    onDebugRestartNewUser: (() -> Unit)? = null,
    onDebugRestartUpgrade: (() -> Unit)? = null,
    onDebugResetAsNewUser: (() -> Unit)? = null,
    onDebugSignOut: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val debugModeStore = remember(context.applicationContext) {
        GradeyDebugModeStore(context.applicationContext)
    }
    var showCredits by remember { mutableStateOf(false) }
    var versionTapCount by remember { mutableIntStateOf(0) }
    var debugUnlocked by remember { mutableStateOf(debugModeStore.isEnabled) }
    var copiedDebugField by remember { mutableStateOf<String?>(null) }
    var pendingDebugAction by remember { mutableStateOf<DebugAction?>(null) }

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
                            GradeyIcons.ArrowLeft,
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

            item {
                OnboardingSupportOptionsContent(
                    catalog = catalog,
                    isSignedIn = isSignedIn,
                    isConfigured = isConfigured,
                    isLoading = isLoading,
                    purchasingOptionID = purchasingOptionID,
                    isRestoring = isRestoring,
                    message = message,
                    onReload = onReload,
                    onPurchasePlan = onPurchasePlan,
                    onPurchaseTip = onPurchaseTip,
                    onRestore = onRestore,
                    onManageSubscription = onManageSubscription,
                    onOpenPrivacyPolicy = onOpenPrivacyPolicy,
                    onOpenTermsOfUse = onOpenTermsOfUse,
                )
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
                            val result = debugModeStore.registerVersionTap(versionTapCount)
                            versionTapCount = result.tapCount
                            if (result.unlocked) debugUnlocked = true
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

                        Text(
                            stringResource(R.string.support_debug_diagnostics),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        DebugCopyableValue(
                            label = stringResource(R.string.support_debug_gradey_id),
                            value = gradeyAccountID,
                            onCopy = { label, value ->
                                context.getSystemService(ClipboardManager::class.java)
                                    ?.setPrimaryClip(ClipData.newPlainText(label, value))
                                copiedDebugField = label
                            },
                        )
                        DebugCopyableValue(
                            label = stringResource(R.string.support_debug_revenuecat_id),
                            value = revenueCatAppUserID,
                            onCopy = { label, value ->
                                context.getSystemService(ClipboardManager::class.java)
                                    ?.setPrimaryClip(ClipData.newPlainText(label, value))
                                copiedDebugField = label
                            },
                        )
                        DebugCopyableValue(
                            label = stringResource(R.string.support_debug_revenuecat_original_id),
                            value = revenueCatOriginalAppUserID,
                            onCopy = { label, value ->
                                context.getSystemService(ClipboardManager::class.java)
                                    ?.setPrimaryClip(ClipData.newPlainText(label, value))
                                copiedDebugField = label
                            },
                        )
                        DebugCopyableValue(
                            label = stringResource(R.string.support_debug_linked_school_id),
                            value = linkedSchoolAccountID,
                            onCopy = { label, value ->
                                context.getSystemService(ClipboardManager::class.java)
                                    ?.setPrimaryClip(ClipData.newPlainText(label, value))
                                copiedDebugField = label
                            },
                        )
                        MetadataRow(
                            stringResource(R.string.support_debug_guest_mode),
                            debugBooleanValue(isGuestMode),
                        )
                        MetadataRow(
                            stringResource(R.string.support_debug_onboarding_v2),
                            debugBooleanValue(hasCompletedOnboardingV2),
                        )
                        MetadataRow(
                            stringResource(R.string.support_debug_onboarding_progress),
                            onboardingProgress?.trim()?.takeIf(String::isNotEmpty)
                                ?: stringResource(R.string.support_debug_unavailable),
                        )
                        copiedDebugField?.let { copiedField ->
                            Text(
                                stringResource(R.string.support_debug_copied, copiedField),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        Text(
                            stringResource(R.string.support_debug_actions),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        if (onDebugRestartNewUser == null && onDebugRestartUpgrade == null) {
                            OutlinedButton(
                                onClick = { pendingDebugAction = DebugAction.RESTART_ONBOARDING },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(stringResource(R.string.support_debug_restart_onboarding))
                            }
                        } else {
                            onDebugRestartNewUser?.let {
                                Button(
                                    onClick = { pendingDebugAction = DebugAction.RESTART_NEW_USER },
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text(stringResource(R.string.support_debug_restart_new_user))
                                }
                            }
                            onDebugRestartUpgrade?.let {
                                OutlinedButton(
                                    onClick = { pendingDebugAction = DebugAction.RESTART_UPGRADE },
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text(stringResource(R.string.support_debug_restart_upgrade))
                                }
                            }
                        }
                        onDebugResetAsNewUser?.let {
                            OutlinedButton(
                                onClick = { pendingDebugAction = DebugAction.RESET_AS_NEW_USER },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(stringResource(R.string.support_debug_reset_new_user))
                            }
                        }
                        onDebugSignOut?.let {
                            OutlinedButton(
                                onClick = { pendingDebugAction = DebugAction.SIGN_OUT },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(stringResource(R.string.support_debug_sign_out))
                            }
                        }
                        OutlinedButton(
                            onClick = { pendingDebugAction = DebugAction.CLEAR_CACHE },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(stringResource(R.string.support_debug_clear_cache))
                        }
                        TextButton(
                            onClick = {
                                debugModeStore.isEnabled = false
                                debugUnlocked = false
                                versionTapCount = 0
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(stringResource(R.string.support_debug_disable))
                        }
                    }
                }
            }
        }
    }

    if (showCredits) {
        AlertDialog(
            onDismissRequest = { showCredits = false },
            icon = { Icon(GradeyIcons.Information, contentDescription = null) },
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
                    TextButton(onClick = onOpenDeveloperInstagram) {
                        Text(stringResource(R.string.credits_developer_instagram))
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showCredits = false }) {
                    Text(stringResource(R.string.support_done))
                }
            },
        )
    }

    pendingDebugAction?.let { action ->
        val title = when (action) {
            DebugAction.RESTART_ONBOARDING,
            DebugAction.RESTART_NEW_USER -> stringResource(R.string.support_debug_restart_new_user)
            DebugAction.RESTART_UPGRADE -> stringResource(R.string.support_debug_restart_upgrade)
            DebugAction.RESET_AS_NEW_USER -> stringResource(R.string.support_debug_reset_new_user)
            DebugAction.SIGN_OUT -> stringResource(R.string.support_debug_sign_out)
            DebugAction.CLEAR_CACHE -> stringResource(R.string.support_debug_clear_cache)
        }
        val messageText = when (action) {
            DebugAction.RESTART_ONBOARDING -> stringResource(R.string.support_debug_restart_onboarding_confirm_message)
            DebugAction.RESTART_NEW_USER -> stringResource(R.string.support_debug_restart_new_user_confirm_message)
            DebugAction.RESTART_UPGRADE -> stringResource(R.string.support_debug_restart_upgrade_confirm_message)
            DebugAction.RESET_AS_NEW_USER -> stringResource(R.string.support_debug_reset_new_user_confirm_message)
            DebugAction.SIGN_OUT -> stringResource(R.string.support_debug_sign_out_confirm_message)
            DebugAction.CLEAR_CACHE -> stringResource(R.string.support_debug_clear_cache_confirm_message)
        }
        AlertDialog(
            onDismissRequest = { pendingDebugAction = null },
            title = { Text(title) },
            text = { Text(messageText) },
            confirmButton = {
                Button(
                    onClick = {
                        when (action) {
                            DebugAction.RESTART_ONBOARDING -> onRestartOnboarding()
                            DebugAction.RESTART_NEW_USER -> onDebugRestartNewUser?.invoke()
                            DebugAction.RESTART_UPGRADE -> onDebugRestartUpgrade?.invoke()
                            DebugAction.RESET_AS_NEW_USER -> onDebugResetAsNewUser?.invoke()
                            DebugAction.SIGN_OUT -> onDebugSignOut?.invoke()
                            DebugAction.CLEAR_CACHE -> onClearCache()
                        }
                        pendingDebugAction = null
                    },
                ) {
                    Text(stringResource(R.string.support_debug_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDebugAction = null }) {
                    Text(stringResource(R.string.account_cancel))
                }
            },
        )
    }
}

/**
 * The Google Play support catalog content shared by the account screen and upgrade onboarding.
 */
@Composable
fun OnboardingSupportOptionsContent(
    catalog: SupportCatalog?,
    isSignedIn: Boolean,
    isConfigured: Boolean,
    isLoading: Boolean,
    purchasingOptionID: String?,
    isRestoring: Boolean,
    message: String?,
    onReload: () -> Unit,
    onPurchasePlan: (SupportPlanOption) -> Unit,
    onPurchaseTip: (String) -> Unit,
    onRestore: () -> Unit,
    onManageSubscription: () -> Unit,
    onOpenPrivacyPolicy: () -> Unit,
    onOpenTermsOfUse: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val actionsEnabled = enabled && !isLoading && purchasingOptionID == null && !isRestoring

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg),
    ) {
        when {
            isLoading && catalog == null -> {
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

            catalog == null -> {
                GradeySectionCard(title = stringResource(R.string.support_unavailable_title)) {
                    Text(
                        if (isConfigured) {
                            message ?: stringResource(R.string.support_unavailable_message)
                        } else {
                            stringResource(R.string.support_not_configured)
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(onClick = onReload, enabled = enabled && !isLoading) {
                        Text(stringResource(R.string.support_retry))
                    }
                }
            }

            else -> {
                val loadedCatalog = catalog
                val entitlement = loadedCatalog.entitlement
                val initialInterval = entitlement.interval ?: SupportBillingInterval.MONTHLY
                val entitlementIdentity = entitlement.selectionIdentity
                var selectedEntitlementIdentity by rememberSaveable {
                    mutableStateOf(entitlementIdentity)
                }
                var selectedIntervalName by rememberSaveable {
                    mutableStateOf(initialInterval.name)
                }
                val selectedInterval = if (selectedEntitlementIdentity == entitlementIdentity) {
                    SupportBillingInterval.entries.firstOrNull { it.name == selectedIntervalName }
                        ?: initialInterval
                } else {
                    initialInterval
                }
                LaunchedEffect(entitlementIdentity) {
                    if (selectedEntitlementIdentity != entitlementIdentity) {
                        selectedEntitlementIdentity = entitlementIdentity
                        selectedIntervalName = initialInterval.name
                    }
                }
                if (loadedCatalog.entitlement.tier != GradeySupportTier.NONE) {
                    ActiveSupportCard(
                        catalog = loadedCatalog,
                        enabled = actionsEnabled,
                        onManageSubscription = onManageSubscription,
                    )
                }

                if (loadedCatalog.plans.isNotEmpty()) {
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
                                    onClick = {
                                        selectedEntitlementIdentity = entitlementIdentity
                                        selectedIntervalName = interval.name
                                    },
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
                                    enabled = actionsEnabled,
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
                                    isBusy = !actionsEnabled,
                                    isPurchasing = purchasingOptionID == plan.id,
                                    onPurchase = { onPurchasePlan(plan) },
                                )
                            }
                    }
                }

                if (loadedCatalog.tips.isNotEmpty()) {
                    GradeySectionCard(title = stringResource(R.string.support_tips_title)) {
                        Text(
                            stringResource(R.string.support_tips_message),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        loadedCatalog.tips.forEach { tip ->
                            OutlinedButton(
                                onClick = { onPurchaseTip(tip.id) },
                                modifier = Modifier.fillMaxWidth(),
                                enabled = actionsEnabled,
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

                GradeySectionCard {
                    Button(
                        onClick = onRestore,
                        modifier = Modifier.fillMaxWidth(),
                        enabled = isSignedIn && actionsEnabled,
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
                        TextButton(onClick = onOpenPrivacyPolicy, enabled = enabled) {
                            Text(stringResource(R.string.privacy_policy))
                        }
                        TextButton(onClick = onOpenTermsOfUse, enabled = enabled) {
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
}

@Composable
private fun DebugCopyableValue(
    label: String,
    value: String?,
    onCopy: (String, String) -> Unit,
) {
    val normalizedValue = value?.trim()?.takeIf(String::isNotEmpty)
    TextButton(
        onClick = { normalizedValue?.let { onCopy(label, it) } },
        modifier = Modifier.fillMaxWidth(),
        enabled = normalizedValue != null,
        contentPadding = PaddingValues(vertical = GradeySpacing.xs),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(GradeySpacing.xs),
        ) {
            Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                normalizedValue ?: stringResource(R.string.support_debug_unavailable),
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun debugBooleanValue(value: Boolean?): String = when (value) {
    true -> stringResource(R.string.support_debug_yes)
    false -> stringResource(R.string.support_debug_no)
    null -> stringResource(R.string.support_debug_unavailable)
}

@Composable
private fun ActiveSupportCard(
    catalog: SupportCatalog,
    enabled: Boolean,
    onManageSubscription: () -> Unit,
) {
    val entitlement = catalog.entitlement
    GradeySectionCard(title = stringResource(R.string.support_active_title)) {
        Icon(GradeyIcons.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
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
        Button(onClick = onManageSubscription, enabled = enabled) {
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
    val canPurchase = SupportPlanEligibility.canPurchase(current, plan)
    OutlinedButton(
        onClick = onPurchase,
        modifier = Modifier.fillMaxWidth(),
        enabled = isSignedIn && !isBusy && canPurchase,
    ) {
        Icon(GradeyIcons.Favourite, contentDescription = null)
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

/**
 * Changes only when the active subscription itself changes. Catalog refreshes may replace the
 * entitlement instance or update renewal metadata without resetting the interval chosen by the
 * user in the picker.
 */
private val SupportEntitlement.selectionIdentity: String
    get() = listOf(
        tier.name,
        productIdentifier.orEmpty(),
        interval?.name.orEmpty(),
    ).joinToString(separator = "|")

private enum class DebugAction {
    RESTART_ONBOARDING,
    RESTART_NEW_USER,
    RESTART_UPGRADE,
    RESET_AS_NEW_USER,
    SIGN_OUT,
    CLEAR_CACHE,
}
