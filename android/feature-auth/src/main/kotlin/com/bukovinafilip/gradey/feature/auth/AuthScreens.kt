package com.bukovinafilip.gradey.feature.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
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
import androidx.compose.ui.text.font.FontWeight
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing

@Composable
fun AgeAttestationScreen(
    onConfirm: (AgeAttestationKind) -> Unit,
    onOpenPrivacyPolicy: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var pendingParentalKind by remember { mutableStateOf<AgeAttestationKind?>(null) }
    var parentConfirmed by remember { mutableStateOf(false) }
    val pending = pendingParentalKind

    GradeyScreen(modifier = modifier.statusBarsPadding()) {
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
    onGoogleSignIn: () -> Unit,
    onContinueWithoutAccount: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    GradeyScreen(modifier = modifier) {
        GradeyHero(
            title = "Gradey ID",
            subtitle = "Sync linked school accounts, grade history, and new-mark notifications across your Android devices.",
        )

        GradeySectionCard(title = "Sign in") {
            Text(
                "Use your Google account to create or open a Gradey ID. School credentials stay encrypted on device or in provider-secret storage when you link an account.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Button(
                modifier = Modifier.fillMaxWidth(),
                enabled = !isLoading,
                onClick = onGoogleSignIn,
            ) {
                Icon(Icons.Default.Person, contentDescription = null)
                Text(if (isLoading) "Signing in" else "Continue with Google")
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
