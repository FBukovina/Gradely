package com.bukovinafilip.gradey.feature.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.model.AppLanguage
import com.bukovinafilip.gradey.model.OnboardingAccountIntent
import com.bukovinafilip.gradey.ui.AppLanguagePicker
import com.bukovinafilip.gradey.ui.GradeyColors
import com.bukovinafilip.gradey.ui.GradeyIcons
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing

@Composable
fun GradeyCheckingScreen(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.radialGradient(
                    listOf(
                        GradeyColors.Primary.copy(alpha = 0.28f),
                        MaterialTheme.colorScheme.background,
                    ),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(GradeySpacing.xl),
        ) {
            Text(
                "Gradey",
                color = MaterialTheme.colorScheme.onBackground,
                fontSize = 48.sp,
                fontWeight = FontWeight.Bold,
            )
            CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
            Text(
                stringResource(R.string.auth_restoring_account),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
fun OnboardingWelcomeScreen(
    appLanguage: AppLanguage,
    onAppLanguageChange: (AppLanguage) -> Unit,
    onContinue: () -> Unit,
    modifier: Modifier = Modifier,
    onLogIn: (() -> Unit)? = null,
) {
    GradeyScreen(modifier = modifier.statusBarsPadding().verticalScroll(rememberScrollState())) {
        GradeyHero(
            title = stringResource(R.string.onboarding_welcome_title),
            subtitle = stringResource(R.string.onboarding_welcome_body),
        )
        GradeySectionCard(title = stringResource(R.string.onboarding_benefits_title)) {
            OnboardingBenefit(
                title = stringResource(R.string.onboarding_welcome_benefit_today_title),
                body = stringResource(R.string.onboarding_welcome_benefit_today_body),
            )
            OnboardingBenefit(
                title = stringResource(R.string.onboarding_welcome_benefit_insights_title),
                body = stringResource(R.string.onboarding_welcome_benefit_insights_body),
            )
            OnboardingBenefit(
                title = stringResource(R.string.onboarding_welcome_benefit_extras_title),
                body = stringResource(R.string.onboarding_welcome_benefit_extras_body),
            )
        }
        GradeySectionCard(title = stringResource(com.bukovinafilip.gradey.ui.R.string.language_title)) {
            AppLanguagePicker(
                selection = appLanguage,
                onSelectionChange = onAppLanguageChange,
            )
        }
        Button(
            modifier = Modifier.fillMaxWidth(),
            onClick = onContinue,
        ) {
            Text(stringResource(R.string.onboarding_get_started))
        }
        if (onLogIn != null) {
            OutlinedButton(
                modifier = Modifier.fillMaxWidth(),
                onClick = onLogIn,
            ) {
                Text(stringResource(R.string.onboarding_log_in))
            }
        }
    }
}

@Composable
private fun OnboardingBenefit(title: String, body: String) {
    Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.xs)) {
        Text(title, fontWeight = FontWeight.SemiBold)
        Text(
            body,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
private fun OnboardingProgressHeader(
    position: Int,
    count: Int,
    onBack: (() -> Unit)?,
    backEnabled: Boolean = true,
) {
    val safeCount = count.coerceAtLeast(1)
    val safePosition = position.coerceIn(1, safeCount)
    Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                TextButton(onClick = onBack, enabled = backEnabled) {
                    Text(stringResource(R.string.auth_back))
                }
            }
            Spacer(Modifier.weight(1f))
            Text(
                text = stringResource(R.string.onboarding_progress, safePosition, safeCount),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
            )
        }
        LinearProgressIndicator(
            progress = { safePosition.toFloat() / safeCount.toFloat() },
            modifier = Modifier
                .fillMaxWidth()
                .clearAndSetSemantics {},
            color = MaterialTheme.colorScheme.primary,
            trackColor = MaterialTheme.colorScheme.surfaceVariant,
        )
    }
}

@Composable
fun OnboardingNotificationsScreen(
    onEnable: () -> Unit,
    onNotNow: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    isWorking: Boolean = false,
    progressPosition: Int? = null,
    progressCount: Int? = null,
) {
    GradeyScreen(modifier = modifier.statusBarsPadding().verticalScroll(rememberScrollState())) {
        if (progressPosition != null && progressCount != null) {
            OnboardingProgressHeader(progressPosition, progressCount, onBack, backEnabled = !isWorking)
        } else {
            TextButton(onClick = onBack, enabled = !isWorking) { Text(stringResource(R.string.auth_back)) }
        }
        GradeyHero(
            title = stringResource(R.string.onboarding_notifications_title),
            subtitle = stringResource(R.string.onboarding_notifications_body),
        )
        GradeySectionCard(title = stringResource(R.string.onboarding_notifications_control_title)) {
            Text(stringResource(R.string.onboarding_notifications_control_body))
        }
        if (isWorking) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        Button(modifier = Modifier.fillMaxWidth(), enabled = !isWorking, onClick = onEnable) {
            Text(stringResource(R.string.onboarding_notifications_enable))
        }
        OutlinedButton(modifier = Modifier.fillMaxWidth(), enabled = !isWorking, onClick = onNotNow) {
            Text(stringResource(R.string.onboarding_notifications_not_now))
        }
    }
}

@Composable
fun OnboardingReadyScreen(
    isGuestMode: Boolean,
    notificationsEnabled: Boolean,
    onFinish: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    schoolCloudLinkFailed: Boolean = false,
    schoolCloudLinkErrorMessage: String? = null,
    isRetryingSchoolCloudLink: Boolean = false,
    onRetrySchoolCloudLink: (() -> Unit)? = null,
    notificationSyncErrorMessage: String? = null,
    notificationSyncPending: Boolean = false,
    isRetryingNotificationSync: Boolean = false,
    isFinishing: Boolean = false,
    onRetryNotificationSync: (() -> Unit)? = null,
    showNotificationSettingsAction: Boolean = false,
    onOpenNotificationSettings: (() -> Unit)? = null,
    progressPosition: Int? = null,
    progressCount: Int? = null,
) {
    val isWorking = isRetryingSchoolCloudLink || isRetryingNotificationSync || isFinishing
    GradeyScreen(modifier = modifier.statusBarsPadding().verticalScroll(rememberScrollState())) {
        if (progressPosition != null && progressCount != null) {
            OnboardingProgressHeader(progressPosition, progressCount, onBack, backEnabled = !isWorking)
        } else {
            TextButton(onClick = onBack, enabled = !isWorking) { Text(stringResource(R.string.auth_back)) }
        }
        GradeyHero(
            title = stringResource(R.string.onboarding_ready_title),
            subtitle = stringResource(R.string.onboarding_ready_body),
        )
        GradeySectionCard(title = stringResource(R.string.onboarding_ready_summary)) {
            Text(stringResource(R.string.onboarding_ready_bakalari_connected))
            Text(
                stringResource(
                    if (isGuestMode) R.string.onboarding_ready_account_local else R.string.onboarding_ready_account_gradey_id,
                ),
            )
            Text(
                stringResource(
                    if (notificationsEnabled) {
                        R.string.onboarding_ready_notifications_enabled
                    } else {
                        R.string.onboarding_ready_notifications_off
                    },
                ),
            )
        }
        if (schoolCloudLinkFailed) {
            GradeySectionCard(title = stringResource(R.string.onboarding_school_link_warning_title)) {
                Text(
                    text = stringResource(R.string.onboarding_school_link_warning_body),
                    color = MaterialTheme.colorScheme.error,
                )
                if (!schoolCloudLinkErrorMessage.isNullOrBlank()) {
                    Text(
                        text = schoolCloudLinkErrorMessage,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (onRetrySchoolCloudLink != null) {
                    Button(
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isWorking,
                        onClick = onRetrySchoolCloudLink,
                    ) {
                        Text(
                            stringResource(
                                if (isRetryingSchoolCloudLink) {
                                    R.string.onboarding_upgrade_retrying
                                } else {
                                    R.string.onboarding_upgrade_retry
                                },
                            ),
                        )
                    }
                }
            }
        }
        if (notificationSyncPending || !notificationSyncErrorMessage.isNullOrBlank()) {
            GradeySectionCard(title = stringResource(R.string.onboarding_notification_sync_warning_title)) {
                Text(
                    text = stringResource(R.string.onboarding_notification_sync_warning_body),
                    color = MaterialTheme.colorScheme.error,
                )
                if (!notificationSyncErrorMessage.isNullOrBlank()) {
                    Text(
                        text = notificationSyncErrorMessage,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (onRetryNotificationSync != null) {
                    Button(
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isWorking,
                        onClick = onRetryNotificationSync,
                    ) {
                        Text(
                            stringResource(
                                if (isRetryingNotificationSync) {
                                    R.string.onboarding_upgrade_retrying
                                } else {
                                    R.string.onboarding_notification_sync_retry
                                },
                            ),
                        )
                    }
                }
            }
        }
        if (showNotificationSettingsAction && onOpenNotificationSettings != null) {
            OutlinedButton(
                modifier = Modifier.fillMaxWidth(),
                enabled = !isWorking,
                onClick = onOpenNotificationSettings,
            ) {
                Text(stringResource(R.string.onboarding_open_notification_settings))
            }
        }
        Button(modifier = Modifier.fillMaxWidth(), enabled = !isWorking, onClick = onFinish) {
            Text(stringResource(R.string.onboarding_ready_open))
        }
    }
}

@Composable
fun OnboardingUpgradeSupportScreen(
    onFinish: () -> Unit,
    modifier: Modifier = Modifier,
    schoolCloudLinkFailed: Boolean = false,
    schoolCloudLinkErrorMessage: String? = null,
    mealsCloudLinkFailed: Boolean = false,
    mealsCloudLinkErrorMessage: String? = null,
    isWorking: Boolean = false,
    isRetryingSchoolCloudLink: Boolean = false,
    isRetryingMealsCloudLink: Boolean = false,
    canFinish: Boolean = true,
    onRetrySchoolCloudLink: (() -> Unit)? = null,
    onRetryMealsCloudLink: (() -> Unit)? = null,
    progressPosition: Int? = null,
    progressCount: Int? = null,
    supportOptionsContent: @Composable () -> Unit = {},
) {
    GradeyScreen(modifier = modifier.statusBarsPadding().verticalScroll(rememberScrollState())) {
        if (progressPosition != null && progressCount != null) {
            OnboardingProgressHeader(progressPosition, progressCount, onBack = null)
        }
        GradeyHero(
            title = stringResource(R.string.onboarding_upgrade_support_title),
            subtitle = stringResource(R.string.onboarding_upgrade_support_body),
        )
        if (schoolCloudLinkFailed) {
            OnboardingUpgradeConnectionWarning(
                bodyResource = R.string.onboarding_sync_warning_school,
                errorMessage = schoolCloudLinkErrorMessage,
                isWorking = isWorking,
                isRetrying = isRetryingSchoolCloudLink,
                onRetry = onRetrySchoolCloudLink,
            )
        }
        if (mealsCloudLinkFailed) {
            OnboardingUpgradeConnectionWarning(
                bodyResource = R.string.onboarding_sync_warning_meals,
                errorMessage = mealsCloudLinkErrorMessage,
                isWorking = isWorking,
                isRetrying = isRetryingMealsCloudLink,
                onRetry = onRetryMealsCloudLink,
            )
        }
        if (isWorking) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        supportOptionsContent()
        Button(
            modifier = Modifier.fillMaxWidth(),
            enabled = canFinish && !isWorking,
            onClick = onFinish,
        ) {
            Text(stringResource(R.string.onboarding_upgrade_support_continue))
        }
    }
}

@Composable
private fun OnboardingUpgradeConnectionWarning(
    bodyResource: Int,
    errorMessage: String?,
    isWorking: Boolean,
    isRetrying: Boolean,
    onRetry: (() -> Unit)?,
) {
    GradeySectionCard(title = stringResource(R.string.onboarding_sync_warning_title)) {
        Text(
            text = stringResource(bodyResource),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (!errorMessage.isNullOrBlank()) {
            Text(
                text = errorMessage,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (onRetry != null) {
            Button(
                modifier = Modifier.fillMaxWidth(),
                enabled = !isWorking,
                onClick = onRetry,
            ) {
                Text(
                    stringResource(
                        if (isRetrying) {
                            R.string.onboarding_sync_warning_retrying
                        } else {
                            R.string.onboarding_sync_warning_retry
                        },
                    ),
                )
            }
        }
    }
}

@Composable
fun AgeAttestationScreen(
    onConfirm: (AgeAttestationKind) -> Unit,
    onOpenPrivacyPolicy: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var pendingParentalKind by remember { mutableStateOf<AgeAttestationKind?>(null) }
    var parentConfirmed by remember { mutableStateOf(false) }
    val pending = pendingParentalKind

    GradeyScreen(modifier = modifier.statusBarsPadding().verticalScroll(rememberScrollState())) {
        if (pending == null) {
            GradeyHero(
                title = stringResource(R.string.age_title),
                subtitle = stringResource(R.string.age_body),
            )
            GradeySectionCard(title = stringResource(R.string.age_choose_option)) {
                AgeChoiceButton(
                    title = stringResource(R.string.age_sixteen_or_older),
                    subtitle = stringResource(R.string.age_sixteen_or_older_body),
                    onClick = { onConfirm(AgeAttestationKind.SIXTEEN_OR_OLDER) },
                )
                AgeChoiceButton(
                    title = stringResource(R.string.age_thirteen_to_fifteen),
                    subtitle = stringResource(R.string.age_parent_required),
                    onClick = {
                        pendingParentalKind = AgeAttestationKind.THIRTEEN_TO_FIFTEEN_WITH_PARENT
                        parentConfirmed = false
                    },
                )
                AgeChoiceButton(
                    title = stringResource(R.string.age_under_thirteen),
                    subtitle = stringResource(R.string.age_parent_required),
                    onClick = {
                        pendingParentalKind = AgeAttestationKind.UNDER_THIRTEEN
                        parentConfirmed = false
                    },
                )
                TextButton(onClick = onOpenPrivacyPolicy) {
                    Text(stringResource(R.string.age_privacy_policy))
                }
            }
        } else {
            GradeyHero(
                title = if (pending == AgeAttestationKind.UNDER_THIRTEEN) {
                    stringResource(R.string.age_under_thirteen)
                } else {
                    stringResource(R.string.age_thirteen_to_fifteen)
                },
                subtitle = stringResource(R.string.age_parent_review_body),
            )
            GradeySectionCard(title = stringResource(R.string.age_parent_confirmation)) {
                Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
                    Checkbox(
                        checked = parentConfirmed,
                        onCheckedChange = { parentConfirmed = it },
                    )
                    Text(stringResource(R.string.age_parent_agreement))
                }
                TextButton(onClick = onOpenPrivacyPolicy) {
                    Text(stringResource(R.string.age_privacy_policy))
                }
                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = parentConfirmed,
                    onClick = { onConfirm(pending) },
                ) {
                    Text(stringResource(R.string.age_continue))
                }
                TextButton(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        pendingParentalKind = null
                        parentConfirmed = false
                    },
                ) {
                    Text(stringResource(R.string.age_choose_different))
                }
            }
        }
    }
}

@Composable
private fun AgeChoiceButton(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    OutlinedButton(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(GradeySpacing.xs),
        ) {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun GradeyIdLoginScreen(
    isLoading: Boolean,
    onGoogleSignIn: () -> Unit,
    onOpenHelp: () -> Unit,
    onOpenGitHub: () -> Unit,
    modifier: Modifier = Modifier,
    errorMessage: String? = null,
    isGoogleSignInAvailable: Boolean = true,
    isUpgradeJourney: Boolean = false,
    accountIntent: OnboardingAccountIntent? = null,
    progressPosition: Int? = null,
    progressCount: Int? = null,
    onContinueWithoutAccount: (() -> Unit)? = null,
    onBack: (() -> Unit)? = null,
) {
    GradeyScreen(modifier = modifier.verticalScroll(rememberScrollState())) {
        if (progressPosition != null && progressCount != null) {
            OnboardingProgressHeader(
                position = progressPosition,
                count = progressCount,
                onBack = onBack,
                backEnabled = !isLoading,
            )
        } else if (onBack != null) {
            TextButton(onClick = onBack, enabled = !isLoading) {
                Text(stringResource(R.string.auth_back))
            }
        }
        GradeyHero(
            title = stringResource(
                when (accountIntent) {
                    OnboardingAccountIntent.GET_STARTED -> R.string.onboarding_account_title
                    OnboardingAccountIntent.LOG_IN -> R.string.onboarding_account_login_title
                    null -> R.string.gradey_id_title
                },
            ),
            subtitle = stringResource(
                when (accountIntent) {
                    OnboardingAccountIntent.GET_STARTED -> R.string.onboarding_account_body
                    OnboardingAccountIntent.LOG_IN -> R.string.onboarding_account_login_body
                    null -> R.string.gradey_id_body
                },
            ),
        )

        GradeySectionCard(title = stringResource(R.string.gradey_id_sign_in)) {
            Text(
                stringResource(
                    if (isGoogleSignInAvailable) {
                        R.string.gradey_id_google_body
                    } else {
                        R.string.gradey_id_unavailable_body
                    },
                ),
                style = MaterialTheme.typography.bodyMedium,
            )
            if (isGoogleSignInAvailable) {
                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                    onClick = onGoogleSignIn,
                ) {
                    Icon(GradeyIcons.User, contentDescription = null)
                    Text(
                        stringResource(
                            if (isLoading) R.string.gradey_id_signing_in else R.string.gradey_id_continue_google,
                        ),
                    )
                }
            }
            if (onContinueWithoutAccount != null) {
                OutlinedButton(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                    onClick = onContinueWithoutAccount,
                ) {
                    Text(
                        stringResource(
                            if (isUpgradeJourney) {
                                R.string.onboarding_upgrade_account_continue_without
                            } else {
                                R.string.gradey_id_continue_without_account
                            },
                        ),
                    )
                }
                Text(
                    stringResource(R.string.gradey_id_local_body),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!errorMessage.isNullOrBlank()) {
                Text(
                    text = errorMessage,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }

        GradeySectionCard {
            Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
                Icon(GradeyIcons.SecurityLock, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.gradey_id_private_title), fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.gradey_id_private_body))
            }
        }
        GradeySectionCard(title = stringResource(R.string.auth_resources_title)) {
            OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onOpenHelp) {
                Text(stringResource(R.string.auth_help))
            }
            OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onOpenGitHub) {
                Text(stringResource(R.string.auth_github))
            }
        }
    }
}
