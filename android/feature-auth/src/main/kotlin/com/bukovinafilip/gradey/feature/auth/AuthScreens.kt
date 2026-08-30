package com.bukovinafilip.gradey.feature.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.model.AppLanguage
import com.bukovinafilip.gradey.model.OnboardingJourney
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
    journey: OnboardingJourney,
    appLanguage: AppLanguage,
    onAppLanguageChange: (AppLanguage) -> Unit,
    onContinue: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GradeyScreen(modifier = modifier.statusBarsPadding().verticalScroll(rememberScrollState())) {
        GradeyHero(
            title = stringResource(
                if (journey == OnboardingJourney.UPGRADE) {
                    R.string.onboarding_upgrade_welcome_title
                } else {
                    R.string.onboarding_welcome_title
                },
            ),
            subtitle = if (journey == OnboardingJourney.UPGRADE) {
                stringResource(R.string.onboarding_upgrade_welcome_body)
            } else {
                stringResource(R.string.onboarding_welcome_body)
            },
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
            Text(
                stringResource(
                    if (journey == OnboardingJourney.UPGRADE) {
                        R.string.onboarding_upgrade_continue
                    } else {
                        R.string.onboarding_get_started
                    },
                ),
            )
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
fun OnboardingNotificationsScreen(
    onEnable: () -> Unit,
    onNotNow: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GradeyScreen(modifier = modifier.statusBarsPadding().verticalScroll(rememberScrollState())) {
        TextButton(onClick = onBack) { Text(stringResource(R.string.auth_back)) }
        GradeyHero(
            title = stringResource(R.string.onboarding_notifications_title),
            subtitle = stringResource(R.string.onboarding_notifications_body),
        )
        GradeySectionCard(title = stringResource(R.string.onboarding_notifications_control_title)) {
            Text(stringResource(R.string.onboarding_notifications_control_body))
        }
        Button(modifier = Modifier.fillMaxWidth(), onClick = onEnable) {
            Text(stringResource(R.string.onboarding_notifications_enable))
        }
        OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onNotNow) {
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
) {
    GradeyScreen(modifier = modifier.statusBarsPadding().verticalScroll(rememberScrollState())) {
        TextButton(onClick = onBack) { Text(stringResource(R.string.auth_back)) }
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
        Button(modifier = Modifier.fillMaxWidth(), onClick = onFinish) {
            Text(stringResource(R.string.onboarding_ready_open))
        }
    }
}

@Composable
fun OnboardingUpgradeSupportScreen(
    isGuestMode: Boolean,
    cloudLinkErrorMessage: String? = null,
    isRetryingCloudLink: Boolean = false,
    onRetryCloudLink: () -> Unit = {},
    onFinish: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GradeyScreen(modifier = modifier.statusBarsPadding().verticalScroll(rememberScrollState())) {
        TextButton(onClick = onBack) { Text(stringResource(R.string.auth_back)) }
        GradeyHero(
            title = stringResource(R.string.onboarding_upgrade_ready_title),
            subtitle = stringResource(R.string.onboarding_upgrade_ready_body),
        )
        GradeySectionCard(title = stringResource(R.string.onboarding_upgrade_account_mode)) {
            Text(
                stringResource(
                    if (isGuestMode) {
                        R.string.onboarding_upgrade_local_mode
                    } else {
                        R.string.onboarding_upgrade_gradey_id_mode
                    },
                ),
            )
            if (!isGuestMode && cloudLinkErrorMessage != null) {
                Text(
                    stringResource(R.string.onboarding_upgrade_link_error, cloudLinkErrorMessage),
                    color = MaterialTheme.colorScheme.error,
                )
                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isRetryingCloudLink,
                    onClick = onRetryCloudLink,
                ) {
                    Text(
                        stringResource(
                            if (isRetryingCloudLink) {
                                R.string.onboarding_upgrade_retrying
                            } else {
                                R.string.onboarding_upgrade_retry
                            },
                        ),
                    )
                }
            } else if (!isGuestMode) {
                Text(stringResource(R.string.onboarding_upgrade_linked))
            }
        }
        Button(modifier = Modifier.fillMaxWidth(), onClick = onFinish) {
            Text(stringResource(R.string.onboarding_continue_to_gradey))
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
    errorMessage: String? = null,
    isGoogleSignInAvailable: Boolean = true,
    onGoogleSignIn: () -> Unit,
    onContinueWithoutAccount: (() -> Unit)? = null,
    onOpenHelp: () -> Unit = {},
    onOpenGitHub: () -> Unit = {},
    onBack: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    GradeyScreen(modifier = modifier.verticalScroll(rememberScrollState())) {
        if (onBack != null) {
            TextButton(onClick = onBack, enabled = !isLoading) {
                Text(stringResource(R.string.auth_back))
            }
        }
        GradeyHero(
            title = stringResource(R.string.gradey_id_title),
            subtitle = stringResource(R.string.gradey_id_body),
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
                    Text(stringResource(R.string.gradey_id_continue_without_account))
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
