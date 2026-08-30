package com.bukovinafilip.gradey.feature.account

import android.app.TimePickerDialog
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.model.AppLanguage
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.NotificationLockScreenDetail
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.ui.AppLanguagePicker
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing
import com.bukovinafilip.gradey.ui.MetadataRow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

@Composable
fun AccountScreen(
    account: GradeyAccount?,
    linkedAccounts: List<LinkedSchoolAccount>,
    appLanguage: AppLanguage = AppLanguage.SYSTEM,
    activeLinkedAccountID: String? = null,
    ageAttestationKind: AgeAttestationKind? = null,
    isGuestMode: Boolean = false,
    isGradeyIdAvailable: Boolean = true,
    isUpdatingFullName: Boolean = false,
    profileErrorMessage: String? = null,
    linkedAccountErrorMessage: String? = null,
    isRefreshingLinkedAccounts: Boolean = false,
    mutatingLinkedAccountID: String? = null,
    showMealsTab: Boolean = true,
    isStravaConnectedOnDevice: Boolean = false,
    isRetryingStravaCloudLink: Boolean = false,
    notificationPreferences: NotificationPreferences = NotificationPreferences.Default,
    notificationPermissionGranted: Boolean = false,
    isUpdatingNotificationPreferences: Boolean = false,
    notificationPreferencesErrorMessage: String? = null,
    isExportingData: Boolean = false,
    isDeletingAccount: Boolean = false,
    privacyDataErrorMessage: String? = null,
    onUpdateFullName: (String) -> Unit = {},
    onConnectGradeyId: () -> Unit = {},
    onRefreshLinkedAccounts: () -> Unit = {},
    onAddSchool: () -> Unit = {},
    onActivateLinkedAccount: (LinkedSchoolAccount) -> Unit = {},
    onReconnectLinkedAccount: (LinkedSchoolAccount) -> Unit = {},
    onToggleLinkedNotifications: (LinkedSchoolAccount, Boolean) -> Unit = { _, _ -> },
    onOpenNotificationSettings: () -> Unit = {},
    onUpdateNotificationPreferences: (NotificationPreferences) -> Unit = {},
    onOpenMeals: () -> Unit = {},
    onRetryStravaCloudLink: () -> Unit = {},
    onOpenPrivacyPolicy: () -> Unit = {},
    onOpenTermsOfUse: () -> Unit = {},
    onExportData: () -> Unit = {},
    onDeleteAccount: () -> Unit = {},
    onOpenSupport: () -> Unit = {},
    onUnlinkLinkedAccount: (LinkedSchoolAccount) -> Unit = {},
    onAppLanguageChange: (AppLanguage) -> Unit = {},
    onShowMealsTabChange: (Boolean) -> Unit = {},
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var pendingUnlink by remember { mutableStateOf<LinkedSchoolAccount?>(null) }
    var deleteConfirmationStage by remember { mutableIntStateOf(0) }
    var fullNameDraft by remember(account?.id, account?.fullName) {
        mutableStateOf(account?.fullName.orEmpty())
    }
    val normalizedFullName = fullNameDraft.trim()
    val isNameValid = normalizedFullName.length in 1..80
    val hasNameChanged = normalizedFullName != account?.fullName?.trim().orEmpty()
    val notificationControlsEnabled = account != null && !isUpdatingNotificationPreferences

    fun showTimePicker(minuteOfDay: Int, onChange: (Int) -> Unit) {
        TimePickerDialog(
            context,
            { _, hour, minute -> onChange(hour * 60 + minute) },
            minuteOfDay.coerceIn(0, 1439) / 60,
            minuteOfDay.coerceIn(0, 1439) % 60,
            true,
        ).show()
    }

    GradeyScreen(modifier = modifier.verticalScroll(rememberScrollState())) {
        GradeyHero("Account", account?.fullName ?: "Local-only mode")
        GradeySectionCard(title = "Profile") {
            Icon(Icons.Default.Person, contentDescription = null)
            account?.let { signedInAccount ->
                val avatarText = signedInAccount.fullName
                    ?.trim()
                    ?.firstOrNull()
                    ?.uppercase()
                    ?: signedInAccount.email?.firstOrNull()?.uppercase()
                    ?: "G"
                Surface(
                    modifier = Modifier.size(64.dp),
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primaryContainer,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            text = avatarText,
                            style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                    }
                }
                MetadataRow(
                    stringResource(R.string.profile_avatar),
                    stringResource(
                        if (signedInAccount.avatarURL.isNullOrBlank()) {
                            R.string.profile_avatar_initials
                        } else {
                            R.string.profile_avatar_connected
                        },
                    ),
                )
            }
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
                Text(stringResource(R.string.notifications_gradey_id_required))
            } else {
                MetadataRow(
                    stringResource(R.string.notifications_device_permission),
                    stringResource(
                        if (notificationPermissionGranted) R.string.notifications_enabled else R.string.notifications_disabled,
                    ),
                )
                OutlinedButton(onClick = onOpenNotificationSettings) {
                    Text(stringResource(R.string.notifications_open_system_settings))
                }

                MetadataRow(
                    stringResource(R.string.notifications_new_marks),
                    stringResource(
                        if (notificationPreferences.newMarksEnabled) R.string.notifications_enabled else R.string.notifications_disabled,
                    ),
                )
                Switch(
                    checked = notificationPreferences.newMarksEnabled,
                    onCheckedChange = {
                        onUpdateNotificationPreferences(notificationPreferences.copy(newMarksEnabled = it))
                    },
                    enabled = notificationControlsEnabled,
                )

                Text(stringResource(R.string.notifications_lock_screen_detail))
                NotificationLockScreenDetail.entries.forEach { detail ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(
                            selected = notificationPreferences.lockScreenDetail == detail,
                            onClick = {
                                onUpdateNotificationPreferences(
                                    notificationPreferences.copy(lockScreenDetail = detail),
                                )
                            },
                            enabled = notificationControlsEnabled && notificationPreferences.newMarksEnabled,
                        )
                        Text(stringResource(detail.labelResource()))
                    }
                }

                MetadataRow(
                    stringResource(R.string.notifications_quiet_hours),
                    stringResource(
                        if (notificationPreferences.quietHoursEnabled) R.string.notifications_enabled else R.string.notifications_disabled,
                    ),
                )
                Switch(
                    checked = notificationPreferences.quietHoursEnabled,
                    onCheckedChange = {
                        onUpdateNotificationPreferences(notificationPreferences.copy(quietHoursEnabled = it))
                    },
                    enabled = notificationControlsEnabled && notificationPreferences.newMarksEnabled,
                )
                OutlinedButton(
                    onClick = {
                        showTimePicker(notificationPreferences.quietHoursStartMinute) { minute ->
                            onUpdateNotificationPreferences(
                                notificationPreferences.copy(quietHoursStartMinute = minute),
                            )
                        }
                    },
                    enabled = notificationControlsEnabled && notificationPreferences.quietHoursEnabled,
                ) {
                    Text(
                        stringResource(
                            R.string.notifications_quiet_start,
                            formatMinute(notificationPreferences.quietHoursStartMinute),
                        ),
                    )
                }
                OutlinedButton(
                    onClick = {
                        showTimePicker(notificationPreferences.quietHoursEndMinute) { minute ->
                            onUpdateNotificationPreferences(
                                notificationPreferences.copy(quietHoursEndMinute = minute),
                            )
                        }
                    },
                    enabled = notificationControlsEnabled && notificationPreferences.quietHoursEnabled,
                ) {
                    Text(
                        stringResource(
                            R.string.notifications_quiet_end,
                            formatMinute(notificationPreferences.quietHoursEndMinute),
                        ),
                    )
                }
                Text(
                    stringResource(
                        R.string.notifications_time_zone,
                        notificationPreferences.quietHoursTimeZone,
                    ),
                )
                if (isUpdatingNotificationPreferences) {
                    Text(stringResource(R.string.notifications_saving))
                }
                if (!notificationPreferencesErrorMessage.isNullOrBlank()) {
                    Text(notificationPreferencesErrorMessage)
                }
            }
        }
        GradeySectionCard(title = androidx.compose.ui.res.stringResource(com.bukovinafilip.gradey.ui.R.string.language_title)) {
            AppLanguagePicker(
                selection = appLanguage,
                onSelectionChange = onAppLanguageChange,
            )
        }
        GradeySectionCard(title = stringResource(R.string.meals_tab_setting_title)) {
            Text(stringResource(R.string.meals_tab_setting_message))
            Switch(checked = showMealsTab, onCheckedChange = onShowMealsTabChange)
        }
        if (account != null) {
            GradeySectionCard(title = "Connected services") {
                Text(
                    "Your linked Bakaláři accounts are encrypted by Gradey and available on your signed-in devices.",
                )
                Button(
                    onClick = onAddSchool,
                    enabled = mutatingLinkedAccountID == null,
                ) {
                    Text(stringResource(R.string.connected_add_school))
                }
                MetadataRow(
                    stringResource(R.string.connected_strava_device),
                    stringResource(
                        if (isStravaConnectedOnDevice) {
                            R.string.connected_status_connected
                        } else {
                            R.string.connected_status_not_connected
                        },
                    ),
                )
                OutlinedButton(onClick = onOpenMeals) {
                    Text(stringResource(R.string.connected_manage_strava))
                }
                val cloudStrava = linkedAccounts.firstOrNull {
                    it.provider == LinkedAccountProvider.STRAVA_CZ
                }
                if (
                    isStravaConnectedOnDevice &&
                    (cloudStrava == null || cloudStrava.status != LinkedAccountStatus.ACTIVE)
                ) {
                    Button(
                        onClick = onRetryStravaCloudLink,
                        enabled = !isRetryingStravaCloudLink && mutatingLinkedAccountID == null,
                    ) {
                        Text(
                            stringResource(
                                if (isRetryingStravaCloudLink) {
                                    R.string.connected_retrying_strava
                                } else {
                                    R.string.connected_retry_strava
                                },
                            ),
                        )
                    }
                }
                Button(
                    onClick = onRefreshLinkedAccounts,
                    enabled = !isRefreshingLinkedAccounts && mutatingLinkedAccountID == null,
                ) {
                    Text(if (isRefreshingLinkedAccounts) "Refreshing…" else "Refresh accounts")
                }
                if (!linkedAccountErrorMessage.isNullOrBlank()) {
                    Text(linkedAccountErrorMessage)
                }
                if (linkedAccounts.isEmpty() && !isRefreshingLinkedAccounts) {
                    Text("No school account is linked to this Gradey ID yet.")
                }
            }
        }
        GradeySectionCard(title = stringResource(R.string.support_title)) {
            Text(stringResource(R.string.support_message))
            Button(onClick = onOpenSupport) {
                Text(stringResource(R.string.support_open))
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
            OutlinedButton(onClick = onOpenPrivacyPolicy) {
                Text(stringResource(R.string.privacy_policy))
            }
            OutlinedButton(onClick = onOpenTermsOfUse) {
                Text(stringResource(R.string.terms_of_use))
            }
            if (account != null) {
                Button(
                    onClick = onExportData,
                    enabled = !isExportingData && !isDeletingAccount,
                ) {
                    Text(
                        stringResource(
                            if (isExportingData) R.string.export_preparing else R.string.export_data,
                        ),
                    )
                }
                Button(
                    onClick = { deleteConfirmationStage = 1 },
                    enabled = !isExportingData && !isDeletingAccount,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    ),
                ) {
                    Text(
                        stringResource(
                            if (isDeletingAccount) R.string.delete_deleting else R.string.delete_account,
                        ),
                    )
                }
                if (!privacyDataErrorMessage.isNullOrBlank()) {
                    Text(
                        text = privacyDataErrorMessage,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }
        GradeySectionCard(title = stringResource(R.string.bakalari_attribution_title)) {
            Text(stringResource(R.string.bakalari_attribution_message))
        }
        if (account != null) {
            Column(
                verticalArrangement = Arrangement.spacedBy(GradeySpacing.md),
                modifier = Modifier.padding(bottom = 8.dp),
            ) {
                linkedAccounts.forEach { linked ->
                    val isMutating = mutatingLinkedAccountID == linked.id
                    val isActive = activeLinkedAccountID == linked.id
                    GradeySectionCard {
                        Text(linked.displayName)
                        MetadataRow("Provider", linked.provider.displayName)
                        MetadataRow("School", linked.schoolName ?: "-")
                        MetadataRow("Status", linked.status.displayName())
                        MetadataRow("On this device", if (isActive) "Active" else "Not active")
                        linked.lastSyncedAt?.let { timestamp ->
                            MetadataRow(
                                stringResource(R.string.connected_last_synced),
                                formatSyncTimestamp(timestamp),
                            )
                        }
                        linked.lastPolledAt?.let { timestamp ->
                            MetadataRow(
                                stringResource(R.string.connected_last_checked),
                                formatSyncTimestamp(timestamp),
                            )
                        }
                        linked.actionRequiredReason?.takeIf(String::isNotBlank)?.let { reason ->
                            Text(reason)
                        }
                        if (
                            linked.provider.isSupportedSchoolProvider &&
                            linked.status == LinkedAccountStatus.ACTION_REQUIRED
                        ) {
                            Button(
                                onClick = { onReconnectLinkedAccount(linked) },
                                enabled = !isMutating,
                            ) {
                                Text("Reconnect")
                            }
                        } else if (
                            linked.provider.isSupportedSchoolProvider &&
                            !isActive &&
                            linked.status == LinkedAccountStatus.ACTIVE
                        ) {
                            Button(
                                onClick = { onActivateLinkedAccount(linked) },
                                enabled = !isMutating && mutatingLinkedAccountID == null,
                            ) {
                                Text(if (isMutating) "Switching…" else "Use this school")
                            }
                        }
                        if (linked.provider.isSupportedSchoolProvider) {
                            MetadataRow(
                                "New-mark notifications",
                                if (linked.notificationsEnabled) "Enabled" else "Disabled",
                            )
                            Switch(
                                checked = linked.notificationsEnabled,
                                onCheckedChange = { onToggleLinkedNotifications(linked, it) },
                                enabled = !isMutating && mutatingLinkedAccountID == null,
                            )
                        } else if (linked.provider == LinkedAccountProvider.STRAVA_CZ) {
                            Text(stringResource(R.string.meals_manage_from_tab))
                        } else {
                            Text("This provider is not available in Gradey for Android yet.")
                        }
                        OutlinedButton(
                            onClick = { pendingUnlink = linked },
                            enabled = !isMutating && mutatingLinkedAccountID == null,
                        ) {
                            Text("Unlink")
                        }
                    }
                }
            }
        }
    }

    pendingUnlink?.let { linked ->
        AlertDialog(
            onDismissRequest = { pendingUnlink = null },
            title = { Text("Unlink ${linked.displayName}?") },
            text = {
                Text(
                    if (linked.provider == LinkedAccountProvider.STRAVA_CZ) {
                        stringResource(R.string.meals_unlink_message)
                    } else {
                        "This removes the school from your Gradey ID. It does not delete the Bakaláři account at your school."
                    },
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        pendingUnlink = null
                        onUnlinkLinkedAccount(linked)
                    },
                ) { Text("Unlink") }
            },
            dismissButton = {
                TextButton(onClick = { pendingUnlink = null }) { Text("Cancel") }
            },
        )
    }

    if (deleteConfirmationStage == 1) {
        AlertDialog(
            onDismissRequest = { deleteConfirmationStage = 0 },
            title = { Text(stringResource(R.string.delete_first_title)) },
            text = { Text(stringResource(R.string.delete_first_message)) },
            confirmButton = {
                Button(onClick = { deleteConfirmationStage = 2 }) {
                    Text(stringResource(R.string.delete_continue))
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmationStage = 0 }) {
                    Text(stringResource(R.string.delete_cancel))
                }
            },
        )
    } else if (deleteConfirmationStage == 2) {
        AlertDialog(
            onDismissRequest = { deleteConfirmationStage = 0 },
            title = { Text(stringResource(R.string.delete_final_title)) },
            text = { Text(stringResource(R.string.delete_final_message)) },
            confirmButton = {
                Button(
                    onClick = {
                        deleteConfirmationStage = 0
                        onDeleteAccount()
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    ),
                ) {
                    Text(stringResource(R.string.delete_final_action))
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmationStage = 0 }) {
                    Text(stringResource(R.string.delete_cancel))
                }
            },
        )
    }
}

private fun LinkedAccountStatus.displayName(): String = when (this) {
    LinkedAccountStatus.ACTIVE -> "Active"
    LinkedAccountStatus.ACTION_REQUIRED -> "Action required"
    LinkedAccountStatus.PAUSED -> "Paused"
    LinkedAccountStatus.LINKING -> "Linking"
    LinkedAccountStatus.FAILED -> "Failed"
}

private fun NotificationLockScreenDetail.labelResource(): Int = when (this) {
    NotificationLockScreenDetail.PRIVATE_SUMMARY -> R.string.notifications_private_summary
    NotificationLockScreenDetail.MARK_AND_SUBJECT -> R.string.notifications_mark_and_subject
    NotificationLockScreenDetail.FULL_DETAILS -> R.string.notifications_full_details
}

private fun formatMinute(minuteOfDay: Int): String = String.format(
    Locale.getDefault(),
    "%02d:%02d",
    minuteOfDay.coerceIn(0, 1439) / 60,
    minuteOfDay.coerceIn(0, 1439) % 60,
)

private fun formatSyncTimestamp(value: String): String = runCatching {
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .format(Instant.parse(value).atZone(ZoneId.systemDefault()))
}.getOrDefault(value)
