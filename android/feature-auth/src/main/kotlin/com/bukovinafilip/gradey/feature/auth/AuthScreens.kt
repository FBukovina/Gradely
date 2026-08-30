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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
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
                "Restoring your account…",
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
        TextButton(onClick = onBack) { Text("Back") }
        GradeyHero(
            title = "Stay up to date",
            subtitle = "Android will ask before Gradey can notify you about new marks. You can change this later in system settings.",
        )
        GradeySectionCard(title = "Notifications stay under your control") {
            Text("Gradey registers this device only after permission is granted. School credentials are never included in notifications.")
        }
        Button(modifier = Modifier.fillMaxWidth(), onClick = onEnable) {
            Text("Enable notifications")
        }
        OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onNotNow) {
            Text("Not now")
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
        TextButton(onClick = onBack) { Text("Back") }
        GradeyHero(
            title = "You're ready",
            subtitle = "Your Bakaláři connection is saved and Gradey can now build your school overview.",
        )
        GradeySectionCard(title = "Setup summary") {
            Text("Bakaláři · Connected")
            Text(if (isGuestMode) "Account · Local only" else "Account · Gradey ID")
            Text(if (notificationsEnabled) "Notifications · Enabled" else "Notifications · Off")
        }
        Button(modifier = Modifier.fillMaxWidth(), onClick = onFinish) {
            Text("Open Gradey")
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
        TextButton(onClick = onBack) { Text("Back") }
        GradeyHero(
            title = "Your connection is ready",
            subtitle = "The existing Bakaláři session was kept during this upgrade.",
        )
        GradeySectionCard(title = "Account mode") {
            Text(
                if (isGuestMode) {
                    "Local-only mode keeps Bakaláři on this device. You can connect Gradey ID later."
                } else {
                    "Gradey ID is connected. Cloud linking will retry safely without replacing your local school session."
                },
            )
            if (!isGuestMode && cloudLinkErrorMessage != null) {
                Text(
                    "Your local Bakaláři connection is safe, but Gradey ID could not link it yet: $cloudLinkErrorMessage",
                    color = MaterialTheme.colorScheme.error,
                )
                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isRetryingCloudLink,
                    onClick = onRetryCloudLink,
                ) {
                    Text(if (isRetryingCloudLink) "Retrying…" else "Retry cloud link")
                }
            } else if (!isGuestMode) {
                Text("Your Bakaláři account is linked to Gradey ID.")
            }
        }
        Button(modifier = Modifier.fillMaxWidth(), onClick = onFinish) {
            Text("Continue to Gradey")
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
                title = "Confirm your age",
                subtitle = "Gradey handles school records, optional AI, and support chat. If you are under 16, a parent or guardian must agree (GDPR).",
            )
            GradeySectionCard(title = "Choose the option that applies") {
                AgeChoiceButton(
                    title = "I am 16 or older",
                    subtitle = "I can use Gradey and agree to the privacy policy.",
                    onClick = { onConfirm(AgeAttestationKind.SIXTEEN_OR_OLDER) },
                )
                AgeChoiceButton(
                    title = "I am 13, 14, or 15",
                    subtitle = "A parent or guardian must agree before school data goes to Gradey.",
                    onClick = {
                        pendingParentalKind = AgeAttestationKind.THIRTEEN_TO_FIFTEEN_WITH_PARENT
                        parentConfirmed = false
                    },
                )
                AgeChoiceButton(
                    title = "I am under 13",
                    subtitle = "A parent or guardian must agree before school data goes to Gradey.",
                    onClick = {
                        pendingParentalKind = AgeAttestationKind.UNDER_THIRTEEN
                        parentConfirmed = false
                    },
                )
                TextButton(onClick = onOpenPrivacyPolicy) { Text("Privacy Policy") }
            }
        } else {
            GradeyHero(
                title = if (pending == AgeAttestationKind.UNDER_THIRTEEN) {
                    "I am under 13"
                } else {
                    "I am 13, 14, or 15"
                },
                subtitle = "Ask a parent or guardian to review the privacy policy. They must agree that Gradey may process your school records, support chat, and optional AI.",
            )
            GradeySectionCard(title = "Parent or guardian confirmation") {
                Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
                    Checkbox(
                        checked = parentConfirmed,
                        onCheckedChange = { parentConfirmed = it },
                    )
                    Text("A parent or guardian has reviewed the privacy policy and agrees.")
                }
                TextButton(onClick = onOpenPrivacyPolicy) { Text("Privacy Policy") }
                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = parentConfirmed,
                    onClick = { onConfirm(pending) },
                ) {
                    Text("Continue")
                }
                TextButton(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        pendingParentalKind = null
                        parentConfirmed = false
                    },
                ) {
                    Text("Choose a different age")
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
    onBack: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    GradeyScreen(modifier = modifier.verticalScroll(rememberScrollState())) {
        if (onBack != null) {
            TextButton(onClick = onBack, enabled = !isLoading) { Text("Back") }
        }
        GradeyHero(
            title = "Gradey ID",
            subtitle = "Sync linked school accounts, grade history, and new-mark notifications across your Android devices.",
        )

        GradeySectionCard(title = "Sign in") {
            Text(
                if (isGoogleSignInAvailable) {
                    "Use your Google account to create or open a Gradey ID. School credentials stay encrypted on device or in provider-secret storage when you link an account."
                } else {
                    "Gradey ID isn't configured in this build. You can continue with encrypted local Bakaláři storage."
                },
                style = MaterialTheme.typography.bodyMedium,
            )
            if (isGoogleSignInAvailable) {
                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                    onClick = onGoogleSignIn,
                ) {
                    Icon(Icons.Default.Person, contentDescription = null)
                    Text(if (isLoading) "Signing in" else "Continue with Google")
                }
            }
            if (onContinueWithoutAccount != null) {
                OutlinedButton(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                    onClick = onContinueWithoutAccount,
                ) {
                    Text("Continue without an account")
                }
                Text(
                    "You can use Bakaláři locally and connect a Gradey ID later without signing in to school again.",
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
                Icon(Icons.Default.Lock, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("Private by default", fontWeight = FontWeight.SemiBold)
                Text("Gradey uses encrypted local storage and only registers push tokens after notification permission is granted.")
            }
        }
    }
}
