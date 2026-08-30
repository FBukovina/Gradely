package com.bukovinafilip.gradey.feature.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing
import com.bukovinafilip.gradey.ui.MetadataRow

@Composable
fun AccountScreen(
    account: GradeyAccount?,
    linkedAccounts: List<LinkedSchoolAccount>,
    ageAttestationKind: AgeAttestationKind? = null,
    isGuestMode: Boolean = false,
    isGradeyIdAvailable: Boolean = true,
    isUpdatingFullName: Boolean = false,
    profileErrorMessage: String? = null,
    onUpdateFullName: (String) -> Unit = {},
    onConnectGradeyId: () -> Unit = {},
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var notifications by remember { mutableStateOf(true) }
    var fullNameDraft by remember(account?.id, account?.fullName) {
        mutableStateOf(account?.fullName.orEmpty())
    }
    val normalizedFullName = fullNameDraft.trim()
    val isNameValid = normalizedFullName.length in 1..80
    val hasNameChanged = normalizedFullName != account?.fullName?.trim().orEmpty()

    GradeyScreen(modifier = modifier) {
        GradeyHero("Account", account?.fullName ?: "Local-only mode")
        GradeySectionCard(title = "Profile") {
            Icon(Icons.Default.Person, contentDescription = null)
            MetadataRow("Email", account?.email ?: "Not connected")
            MetadataRow("Account ID", account?.id ?: "No Gradey ID")
            if (account != null) {
                OutlinedTextField(
                    value = fullNameDraft,
                    onValueChange = { fullNameDraft = it },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isUpdatingFullName,
                    singleLine = true,
                    label = { Text("Full name") },
                    isError = hasNameChanged && !isNameValid,
                    supportingText = {
                        when {
                            hasNameChanged && !isNameValid -> Text("Use between 1 and 80 characters.")
                            profileErrorMessage != null -> Text(profileErrorMessage)
                        }
                    },
                )
                Button(
                    onClick = { onUpdateFullName(normalizedFullName) },
                    enabled = isNameValid && hasNameChanged && !isUpdatingFullName,
                ) {
                    Text(if (isUpdatingFullName) "Saving…" else "Save name")
                }
            } else {
                Text(
                    if (isGuestMode) {
                        "You're continuing without a Gradey ID. Your Bakaláři data stays local on this device."
                    } else {
                        "Gradey ID isn't configured in this build. Your Bakaláři data stays local on this device."
                    },
                )
                if (isGuestMode && isGradeyIdAvailable) {
                    Button(onClick = onConnectGradeyId) { Text("Connect Gradey ID") }
                }
            }
            Button(onClick = onSignOut) {
                Text(if (account == null) "Disconnect Bakaláři" else "Sign out")
            }
        }
        GradeySectionCard(title = "Notifications") {
            Icon(Icons.Default.Notifications, contentDescription = null)
            if (account == null) {
                Text("Cloud notification settings require a Gradey ID.")
            } else {
                MetadataRow("New marks", if (notifications) "Enabled" else "Disabled")
                Switch(checked = notifications, onCheckedChange = { notifications = it })
            }
        }
        GradeySectionCard(title = "Privacy & data") {
            MetadataRow(
                "Age",
                when (ageAttestationKind) {
                    AgeAttestationKind.SIXTEEN_OR_OLDER -> "Confirmed: 16 or older"
                    AgeAttestationKind.THIRTEEN_TO_FIFTEEN_WITH_PARENT,
                    AgeAttestationKind.UNDER_THIRTEEN,
                    -> "Confirmed: under 16 with parent or guardian"
                    null -> "Not confirmed"
                },
            )
            Text("Gradey asks for age confirmation before school data, support chat, or AI leave the device for our servers.")
        }
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(GradeySpacing.md),
            modifier = Modifier.padding(bottom = 8.dp),
        ) {
            items(linkedAccounts, key = { it.id }) { linked ->
                GradeySectionCard {
                    Text(linked.displayName)
                    MetadataRow("Provider", linked.provider.displayName)
                    MetadataRow("School", linked.schoolName ?: "-")
                    MetadataRow("Status", linked.status)
                }
            }
        }
    }
}
