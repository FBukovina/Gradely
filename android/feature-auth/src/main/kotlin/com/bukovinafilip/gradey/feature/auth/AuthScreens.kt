package com.bukovinafilip.gradey.feature.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing

@Composable
fun GradeyIdLoginScreen(
    isLoading: Boolean,
    onGoogleSignIn: () -> Unit,
    onTestingBypass: () -> Unit,
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
            Button(
                modifier = Modifier.fillMaxWidth(),
                enabled = !isLoading,
                onClick = onTestingBypass,
            ) {
                Text("Use demo data")
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

