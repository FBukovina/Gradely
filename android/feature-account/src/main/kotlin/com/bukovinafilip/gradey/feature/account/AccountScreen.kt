package com.bukovinafilip.gradey.feature.account

import android.app.TimePickerDialog
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.vector.ImageVector
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.bukovinafilip.gradey.model.AgeAttestationKind
import com.bukovinafilip.gradey.model.AppLanguage
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.NotificationLockScreenDetail
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.ui.AppLanguagePicker
import com.bukovinafilip.gradey.ui.GradeyIcons
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing
import com.bukovinafilip.gradey.ui.MetadataRow
import java.net.URI
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

internal data class AccountFullNameEditorState(
    val accountID: String?,
    val canonicalFullName: String,
    val draft: String,
    val isDirty: Boolean,
) {
    fun reconciledWith(account: GradeyAccount?): AccountFullNameEditorState {
        val nextAccountID = account?.id
        val nextCanonicalFullName = account?.fullName.orEmpty()
        return when {
            accountID != nextAccountID -> initial(account)
            !isDirty -> copy(
                canonicalFullName = nextCanonicalFullName,
                draft = nextCanonicalFullName,
            )
            canonicalFullName.trim() != nextCanonicalFullName.trim() &&
                draft.trim() == nextCanonicalFullName.trim() -> copy(
                canonicalFullName = nextCanonicalFullName,
                draft = nextCanonicalFullName,
                isDirty = false,
            )
            else -> copy(canonicalFullName = nextCanonicalFullName)
        }
    }

    companion object {
        fun initial(account: GradeyAccount?): AccountFullNameEditorState {
            val canonicalFullName = account?.fullName.orEmpty()
            return AccountFullNameEditorState(
                accountID = account?.id,
                canonicalFullName = canonicalFullName,
                draft = canonicalFullName,
                isDirty = false,
            )
        }
    }
}

private val AccountFullNameEditorStateSaver = Saver<AccountFullNameEditorState, ArrayList<String>>(
    save = { state ->
        arrayListOf(
            state.accountID.orEmpty(),
            (state.accountID != null).toString(),
            state.canonicalFullName,
            state.draft,
            state.isDirty.toString(),
        )
    },
    restore = { saved ->
        val accountIDPresent = saved.getOrNull(1)?.toBooleanStrictOrNull()
        val isDirty = saved.getOrNull(4)?.toBooleanStrictOrNull()
        if (saved.size != 5 || accountIDPresent == null || isDirty == null) {
            null
        } else {
            AccountFullNameEditorState(
                accountID = saved[0].takeIf { accountIDPresent },
                canonicalFullName = saved[2],
                draft = saved[3],
                isDirty = isDirty,
            )
        }
    },
)

@Composable
fun AccountScreen(
    account: GradeyAccount?,
    linkedAccounts: List<LinkedSchoolAccount>,
    selectedDestination: AccountSettingsDestination?,
    hasBakalariConnectionOnDevice: Boolean,
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
    onUpdateFullName: (String) -> Unit,
    onSelectedDestinationChange: (AccountSettingsDestination?) -> Unit,
    onConnectGradeyId: () -> Unit,
    onRefreshLinkedAccounts: () -> Unit,
    onAddSchool: () -> Unit,
    onActivateLinkedAccount: (LinkedSchoolAccount) -> Unit,
    onReconnectLinkedAccount: (LinkedSchoolAccount) -> Unit,
    onToggleLinkedNotifications: (LinkedSchoolAccount, Boolean) -> Unit,
    onOpenNotificationSettings: () -> Unit,
    onRequestNotificationPermission: () -> Unit = onOpenNotificationSettings,
    onUpdateNotificationPreferences: (NotificationPreferences) -> Unit,
    onOpenMeals: () -> Unit,
    onRetryStravaCloudLink: () -> Unit,
    onOpenPrivacyPolicy: () -> Unit,
    onOpenTermsOfUse: () -> Unit,
    onExportData: () -> Unit,
    onDeleteAccount: () -> Unit,
    onOpenSupport: () -> Unit,
    onUnlinkLinkedAccount: (LinkedSchoolAccount) -> Unit,
    onAppLanguageChange: (AppLanguage) -> Unit,
    onShowMealsTabChange: (Boolean) -> Unit,
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var pendingUnlink by remember { mutableStateOf<LinkedSchoolAccount?>(null) }
    var showSignOutConfirmation by remember { mutableStateOf(false) }
    var deleteConfirmationStage by remember { mutableIntStateOf(0) }
    var savedFullNameEditor by rememberSaveable(stateSaver = AccountFullNameEditorStateSaver) {
        mutableStateOf(AccountFullNameEditorState.initial(account))
    }
    val fullNameEditor = savedFullNameEditor.reconciledWith(account)
    LaunchedEffect(fullNameEditor) {
        if (savedFullNameEditor != fullNameEditor) {
            savedFullNameEditor = fullNameEditor
        }
    }
    val fullNameDraft = fullNameEditor.draft
    val normalizedFullName = fullNameDraft.trim()
    val isNameValid = normalizedFullName.length in 1..80
    val hasNameChanged = normalizedFullName != account?.fullName?.trim().orEmpty()
    val hasCloudSchool = linkedAccounts.any {
        it.provider.isSupportedSchoolProvider && it.status == LinkedAccountStatus.ACTIVE
    }
    val notificationsAvailable = account != null && hasCloudSchool
    val notificationControlsEnabled = notificationsAvailable && !isUpdatingNotificationPreferences
    val quietHoursControlsEnabled = notificationControlsEnabled &&
        notificationPreferences.newMarksEnabled &&
        notificationPreferences.quietHoursEnabled

    fun showTimePicker(minuteOfDay: Int, onChange: (Int) -> Unit) {
        TimePickerDialog(
            context,
            { _, hour, minute -> onChange(hour * 60 + minute) },
            minuteOfDay.coerceIn(0, 1439) / 60,
            minuteOfDay.coerceIn(0, 1439) % 60,
            true,
        ).show()
    }

    BoxWithConstraints(modifier = modifier) {
        val paneMode = accountSettingsPaneMode(maxWidth.value)
        val effectiveDestination = resolvedAccountSettingsDestination(paneMode, selectedDestination)
        BackHandler(
            enabled = paneMode == AccountSettingsPaneMode.COMPACT && selectedDestination != null,
        ) {
            onSelectedDestinationChange(null)
        }
        Row(modifier = Modifier.fillMaxSize()) {
            if (paneMode == AccountSettingsPaneMode.EXPANDED || effectiveDestination == null) {
                AccountSettingsOverview(
                    account = account,
                    linkedAccounts = linkedAccounts,
                    notificationPreferences = notificationPreferences,
                    isStravaConnectedOnDevice = isStravaConnectedOnDevice,
                    hasBakalariConnectionOnDevice = hasBakalariConnectionOnDevice,
                    activeLinkedAccountID = activeLinkedAccountID,
                    notificationPermissionGranted = notificationPermissionGranted,
                    notificationsAvailable = notificationsAvailable,
                    selectedDestination = effectiveDestination,
                    onSelect = onSelectedDestinationChange,
                    modifier = if (paneMode == AccountSettingsPaneMode.EXPANDED) {
                        Modifier.weight(0.42f).fillMaxHeight()
                    } else {
                        Modifier.fillMaxSize()
                    },
                )
            }
            if (paneMode == AccountSettingsPaneMode.EXPANDED) {
                Box(
                    Modifier
                        .fillMaxHeight()
                        .width(1.dp)
                        .background(MaterialTheme.colorScheme.outlineVariant),
                )
            }
            if (effectiveDestination != null) {
                key(effectiveDestination) {
                    GradeyScreen(
                        modifier = (if (paneMode == AccountSettingsPaneMode.EXPANDED) {
                            Modifier.weight(0.58f).fillMaxHeight()
                        } else {
                            Modifier.fillMaxSize()
                        }).verticalScroll(rememberScrollState()),
                    ) {
                        if (paneMode == AccountSettingsPaneMode.COMPACT) {
                            TextButton(onClick = { onSelectedDestinationChange(null) }) {
                                Icon(GradeyIcons.ArrowLeft, contentDescription = null)
                                Text(stringResource(R.string.settings_back))
                            }
                        }
                        GradeyHero(
                            stringResource(effectiveDestination.titleResource),
                            stringResource(effectiveDestination.subtitleResource),
                        )
                        if (effectiveDestination == AccountSettingsDestination.ACCOUNT) {
                            GradeySectionCard(title = stringResource(R.string.account_profile)) {
            Icon(GradeyIcons.User, contentDescription = null)
            account?.let { signedInAccount ->
                ProfileAvatar(signedInAccount)
                MetadataRow(
                    stringResource(R.string.profile_avatar),
                    stringResource(
                        if (normalizedProfileAvatarUrl(signedInAccount.avatarURL) == null) {
                            R.string.profile_avatar_initials
                        } else {
                            R.string.profile_avatar_connected
                        },
                    ),
                )
            }
            MetadataRow(
                stringResource(R.string.account_email),
                account?.email ?: stringResource(R.string.account_not_connected),
            )
            MetadataRow(
                stringResource(R.string.account_id),
                account?.id ?: stringResource(R.string.account_no_gradey_id),
            )
            if (account != null) {
                OutlinedTextField(
                    value = fullNameDraft,
                    onValueChange = {
                        savedFullNameEditor = fullNameEditor.copy(
                            draft = it,
                            isDirty = true,
                        )
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(ACCOUNT_FULL_NAME_FIELD_TEST_TAG),
                    enabled = !isUpdatingFullName,
                    singleLine = true,
                    label = { Text(stringResource(R.string.account_full_name)) },
                    isError = hasNameChanged && !isNameValid,
                    supportingText = {
                        when {
                            hasNameChanged && !isNameValid -> Text(stringResource(R.string.account_name_length_error))
                            profileErrorMessage != null -> Text(profileErrorMessage)
                        }
                    },
                )
                Button(
                    onClick = { onUpdateFullName(normalizedFullName) },
                    modifier = Modifier.testTag(ACCOUNT_SAVE_FULL_NAME_TEST_TAG),
                    enabled = isNameValid && hasNameChanged && !isUpdatingFullName,
                ) {
                    Text(
                        stringResource(
                            if (isUpdatingFullName) R.string.account_saving else R.string.account_save_name,
                        ),
                    )
                }
            } else {
                Text(
                    stringResource(
                        if (isGuestMode) {
                            R.string.account_guest_mode_body
                        } else {
                            R.string.account_gradey_id_unavailable_body
                        },
                    ),
                )
                if (isGuestMode && isGradeyIdAvailable) {
                    Button(onClick = onConnectGradeyId) {
                        Text(stringResource(R.string.account_connect_gradey_id))
                    }
                }
            }
            Button(
                onClick = { showSignOutConfirmation = true },
                enabled = mutatingLinkedAccountID == null,
            ) {
                Text(
                    stringResource(
                        if (account == null) R.string.account_disconnect_bakalari else R.string.account_sign_out,
                    ),
                )
            }
                            }
                        }
                        if (effectiveDestination == AccountSettingsDestination.NOTIFICATIONS) {
                            GradeySectionCard(title = stringResource(R.string.account_notifications)) {
            Icon(GradeyIcons.Notification, contentDescription = null)
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

                SettingsSwitchRow(
                    label = stringResource(R.string.notifications_new_marks),
                    checked = notificationPreferences.newMarksEnabled,
                    onCheckedChange = {
                        when (
                            val action = resolveNewMarksToggleAction(
                                requestedEnabled = it,
                                permissionGranted = notificationPermissionGranted,
                            )
                        ) {
                            is NewMarksToggleAction.Persist -> {
                                onUpdateNotificationPreferences(
                                    notificationPreferences.copy(newMarksEnabled = action.enabled),
                                )
                            }
                            NewMarksToggleAction.RequestPermission -> {
                                onRequestNotificationPermission()
                            }
                        }
                    },
                    enabled = notificationControlsEnabled,
                )

                Text(stringResource(R.string.notifications_lock_screen_detail))
                Column(Modifier.selectableGroup()) {
                    NotificationLockScreenDetail.entries.forEach { detail ->
                        SettingsRadioRow(
                            label = stringResource(detail.labelResource()),
                            selected = notificationPreferences.lockScreenDetail == detail,
                            onClick = {
                                onUpdateNotificationPreferences(
                                    notificationPreferences.copy(lockScreenDetail = detail),
                                )
                            },
                            enabled = notificationControlsEnabled && notificationPreferences.newMarksEnabled,
                        )
                    }
                }

                SettingsSwitchRow(
                    label = stringResource(R.string.notifications_quiet_hours),
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
                    enabled = quietHoursControlsEnabled,
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
                    enabled = quietHoursControlsEnabled,
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
                        }
                        if (effectiveDestination == AccountSettingsDestination.APP_PREFERENCES) {
                            GradeySectionCard(title = androidx.compose.ui.res.stringResource(com.bukovinafilip.gradey.ui.R.string.language_title)) {
            AppLanguagePicker(
                selection = appLanguage,
                onSelectionChange = onAppLanguageChange,
            )
        }
                            GradeySectionCard {
            SettingsSwitchRow(
                label = stringResource(R.string.meals_tab_setting_title),
                supportingText = stringResource(R.string.meals_tab_setting_message),
                checked = showMealsTab,
                enabled = true,
                onCheckedChange = onShowMealsTabChange,
            )
                            }
                        }
                        if (effectiveDestination == AccountSettingsDestination.CONNECTED_SERVICES) {
            GradeySectionCard(title = stringResource(R.string.account_connected_services)) {
                Text(
                    stringResource(R.string.account_connected_services_body),
                )
                if (account != null) {
                    Button(
                        onClick = onAddSchool,
                        enabled = mutatingLinkedAccountID == null,
                    ) {
                        Text(stringResource(R.string.connected_add_school))
                    }
                } else {
                    Text(stringResource(R.string.connected_cloud_requires_gradey_id))
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
                    account != null &&
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
                if (account != null) {
                    Button(
                        onClick = onRefreshLinkedAccounts,
                        enabled = !isRefreshingLinkedAccounts && mutatingLinkedAccountID == null,
                    ) {
                        Text(
                            stringResource(
                                if (isRefreshingLinkedAccounts) {
                                    R.string.account_refreshing
                                } else {
                                    R.string.account_refresh_accounts
                                },
                            ),
                        )
                    }
                    if (!linkedAccountErrorMessage.isNullOrBlank()) {
                        Text(linkedAccountErrorMessage)
                    }
                    if (linkedAccounts.isEmpty() && !isRefreshingLinkedAccounts) {
                        Text(stringResource(R.string.account_no_linked_school))
                    }
                }
            }
                        }
                        if (effectiveDestination == AccountSettingsDestination.SUPPORT_ABOUT) {
                            GradeySectionCard(title = stringResource(R.string.support_title)) {
            Text(stringResource(R.string.support_message))
            Button(onClick = onOpenSupport) {
                Text(stringResource(R.string.support_open))
            }
                            }
                        }
                        if (effectiveDestination == AccountSettingsDestination.PRIVACY_DATA) {
                            GradeySectionCard(title = stringResource(R.string.account_privacy_data)) {
            MetadataRow(
                stringResource(R.string.account_age),
                when (ageAttestationKind) {
                    AgeAttestationKind.SIXTEEN_OR_OLDER -> stringResource(R.string.account_age_sixteen_confirmed)
                    AgeAttestationKind.THIRTEEN_TO_FIFTEEN_WITH_PARENT,
                    AgeAttestationKind.UNDER_THIRTEEN,
                    -> stringResource(R.string.account_age_under_sixteen_confirmed)
                    null -> stringResource(R.string.account_age_not_confirmed)
                },
            )
            Text(stringResource(R.string.account_age_body))
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
                    modifier = Modifier.testTag(ACCOUNT_DELETE_ENTRY_TEST_TAG),
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
                        }
                        if (effectiveDestination == AccountSettingsDestination.CONNECTED_SERVICES) {
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
                        MetadataRow(stringResource(R.string.account_provider), linked.provider.displayName)
                        MetadataRow(stringResource(R.string.account_school), linked.schoolName ?: "-")
                        MetadataRow(stringResource(R.string.account_status), linked.status.localizedDisplayName())
                        MetadataRow(
                            stringResource(R.string.account_on_this_device),
                            stringResource(
                                if (isActive) R.string.account_active else R.string.account_not_active,
                            ),
                        )
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
                        if (
                            linked.provider.isSupportedSchoolProvider &&
                            (
                                linked.status == LinkedAccountStatus.ACTION_REQUIRED ||
                                    linked.status == LinkedAccountStatus.FAILED
                            )
                        ) {
                            Text(stringResource(R.string.account_reconnect_reason))
                            Button(
                                onClick = { onReconnectLinkedAccount(linked) },
                                enabled = !isMutating,
                            ) {
                                Text(stringResource(R.string.account_reconnect))
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
                                Text(
                                    stringResource(
                                        if (isMutating) {
                                            R.string.account_switching
                                        } else {
                                            R.string.account_use_this_school
                                        },
                                    ),
                                )
                            }
                        }
                        if (linked.provider.isSupportedSchoolProvider) {
                            SettingsSwitchRow(
                                label = stringResource(R.string.account_new_mark_notifications),
                                supportingText = stringResource(R.string.account_new_mark_notifications_message),
                                checked = linked.notificationsEnabled,
                                onCheckedChange = { onToggleLinkedNotifications(linked, it) },
                                enabled = notificationPreferences.newMarksEnabled &&
                                    !isMutating &&
                                    mutatingLinkedAccountID == null,
                                modifier = Modifier.testTag(
                                    "$ACCOUNT_LINKED_NOTIFICATIONS_TEST_TAG_PREFIX${linked.id}",
                                ),
                            )
                        } else if (linked.provider == LinkedAccountProvider.STRAVA_CZ) {
                            Text(stringResource(R.string.meals_manage_from_tab))
                        } else {
                            Text(stringResource(R.string.account_provider_unavailable))
                        }
                        OutlinedButton(
                            onClick = { pendingUnlink = linked },
                            enabled = !isMutating && mutatingLinkedAccountID == null,
                        ) {
                            Text(stringResource(R.string.account_unlink))
                        }
                    }
                }
            }
                            }
                        }
                    }
                }
            }
        }
    }

    pendingUnlink?.let { linked ->
        AlertDialog(
            onDismissRequest = { pendingUnlink = null },
            title = { Text(stringResource(R.string.account_unlink_title, linked.displayName)) },
            text = {
                Text(
                    if (linked.provider == LinkedAccountProvider.STRAVA_CZ) {
                        stringResource(R.string.meals_unlink_message)
                    } else {
                        stringResource(R.string.account_unlink_school_body)
                    },
                )
            },
            confirmButton = {
                Button(
                    enabled = mutatingLinkedAccountID == null,
                    onClick = {
                        pendingUnlink = null
                        onUnlinkLinkedAccount(linked)
                    },
                ) { Text(stringResource(R.string.account_unlink)) }
            },
            dismissButton = {
                TextButton(onClick = { pendingUnlink = null }) {
                    Text(stringResource(R.string.account_cancel))
                }
            },
        )
    }

    if (showSignOutConfirmation) {
        AlertDialog(
            onDismissRequest = { showSignOutConfirmation = false },
            title = {
                Text(
                    stringResource(
                        if (account == null) {
                            R.string.account_disconnect_title
                        } else {
                            R.string.account_sign_out_title
                        },
                    ),
                )
            },
            text = {
                Text(
                    stringResource(
                        if (account == null) {
                            R.string.account_disconnect_body
                        } else {
                            R.string.account_sign_out_body
                        },
                    ),
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        showSignOutConfirmation = false
                        onSignOut()
                    },
                    enabled = mutatingLinkedAccountID == null,
                ) {
                    Text(
                        stringResource(
                            if (account == null) {
                                R.string.account_disconnect_confirm
                            } else {
                                R.string.account_sign_out_confirm
                            },
                        ),
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { showSignOutConfirmation = false }) {
                    Text(stringResource(R.string.account_cancel))
                }
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

@Composable
internal fun AccountSettingsOverview(
    account: GradeyAccount?,
    linkedAccounts: List<LinkedSchoolAccount>,
    notificationPreferences: NotificationPreferences,
    isStravaConnectedOnDevice: Boolean,
    hasBakalariConnectionOnDevice: Boolean,
    activeLinkedAccountID: String?,
    notificationPermissionGranted: Boolean,
    notificationsAvailable: Boolean,
    selectedDestination: AccountSettingsDestination?,
    onSelect: (AccountSettingsDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val schoolAccounts = linkedAccounts.filter { it.provider.isSupportedSchoolProvider }
    val stravaAccounts = linkedAccounts.filter { it.provider == LinkedAccountProvider.STRAVA_CZ }
    val servicesOverview = accountSettingsServicesOverview(
        hasBakalariConnection = hasBakalariConnectionOnDevice ||
            activeLinkedAccountID != null ||
            schoolAccounts.any { it.status == LinkedAccountStatus.ACTIVE },
        bakalariNeedsAttention = schoolAccounts.any {
            it.status == LinkedAccountStatus.ACTION_REQUIRED || it.status == LinkedAccountStatus.FAILED
        },
        hasStravaConnection = isStravaConnectedOnDevice ||
            stravaAccounts.any { it.status == LinkedAccountStatus.ACTIVE },
        stravaNeedsAttention = stravaAccounts.any {
            it.status == LinkedAccountStatus.ACTION_REQUIRED || it.status == LinkedAccountStatus.FAILED
        },
    )
    val notificationStatus = accountSettingsNotificationStatus(
        isAvailable = notificationsAvailable,
        isEnabled = notificationPreferences.newMarksEnabled,
        isPermissionGranted = notificationPermissionGranted,
        isQuietHoursEnabled = notificationPreferences.quietHoursEnabled,
    )
    GradeyScreen(modifier = modifier.verticalScroll(rememberScrollState())) {
        GradeyHero(
            stringResource(R.string.settings_overview_title),
            stringResource(R.string.settings_overview_subtitle),
        )
        Column(
            modifier = if (selectedDestination != null) Modifier.selectableGroup() else Modifier,
            verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg),
        ) {
            AccountSettingsDestination.entries.forEach { destination ->
                val hasAttention = destination == AccountSettingsDestination.CONNECTED_SERVICES &&
                    (
                        servicesOverview.bakalari == AccountSettingsServiceStatus.ACTION_REQUIRED ||
                            servicesOverview.strava == AccountSettingsServiceStatus.ACTION_REQUIRED
                    )
                val subtitle = when (destination) {
                    AccountSettingsDestination.ACCOUNT -> account?.email
                        ?: stringResource(R.string.account_local_only_mode)
                    AccountSettingsDestination.NOTIFICATIONS -> notificationOverviewText(
                        status = notificationStatus,
                        quietHoursEndMinute = notificationPreferences.quietHoursEndMinute,
                    )
                    AccountSettingsDestination.CONNECTED_SERVICES -> servicesOverviewText(servicesOverview)
                    else -> stringResource(destination.subtitleResource)
                }
                val selectionSemantics = if (selectedDestination != null) {
                    Modifier.semantics {
                        selected = selectedDestination == destination
                        role = Role.Tab
                    }
                } else {
                    Modifier
                }
                Surface(
                    onClick = { onSelect(destination) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(selectionSemantics),
                    shape = RoundedCornerShape(18.dp),
                    color = if (selectedDestination == destination) {
                        MaterialTheme.colorScheme.primaryContainer
                    } else {
                        MaterialTheme.colorScheme.surfaceContainer
                    },
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = destination.icon,
                            contentDescription = null,
                            tint = if (hasAttention) {
                                MaterialTheme.colorScheme.error
                            } else {
                                MaterialTheme.colorScheme.primary
                            },
                            modifier = Modifier.size(26.dp),
                        )
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(3.dp),
                        ) {
                            Text(
                                text = stringResource(destination.titleResource),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = subtitle,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Icon(
                            imageVector = if (hasAttention) GradeyIcons.ErrorCircle else GradeyIcons.ArrowRight,
                            contentDescription = if (hasAttention) {
                                stringResource(R.string.account_status_action_required)
                            } else {
                                null
                            },
                            tint = if (hasAttention) {
                                MaterialTheme.colorScheme.error
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun servicesOverviewText(overview: AccountSettingsServicesOverview): String = stringResource(
    R.string.settings_overview_services_summary,
    stringResource(overview.bakalari.bakalariStatusResource),
    stringResource(overview.strava.stravaStatusResource),
)

private val AccountSettingsServiceStatus.bakalariStatusResource: Int
    get() = when (this) {
        AccountSettingsServiceStatus.CONNECTED -> R.string.settings_overview_bakalari_connected
        AccountSettingsServiceStatus.NOT_CONNECTED -> R.string.settings_overview_bakalari_not_connected
        AccountSettingsServiceStatus.ACTION_REQUIRED -> R.string.settings_overview_bakalari_action_required
    }

private val AccountSettingsServiceStatus.stravaStatusResource: Int
    get() = when (this) {
        AccountSettingsServiceStatus.CONNECTED -> R.string.settings_overview_strava_connected
        AccountSettingsServiceStatus.NOT_CONNECTED -> R.string.settings_overview_strava_not_connected
        AccountSettingsServiceStatus.ACTION_REQUIRED -> R.string.settings_overview_strava_action_required
    }

@Composable
private fun notificationOverviewText(
    status: AccountSettingsNotificationStatus,
    quietHoursEndMinute: Int,
): String = when (status) {
    AccountSettingsNotificationStatus.UNAVAILABLE ->
        stringResource(R.string.settings_overview_notifications_unavailable)
    AccountSettingsNotificationStatus.OFF ->
        stringResource(R.string.settings_overview_notifications_off)
    AccountSettingsNotificationStatus.PERMISSION_REQUIRED ->
        stringResource(R.string.settings_overview_notifications_permission_required)
    AccountSettingsNotificationStatus.QUIET_HOURS -> stringResource(
        R.string.settings_overview_notifications_quiet_until,
        formatMinute(quietHoursEndMinute),
    )
    AccountSettingsNotificationStatus.ON ->
        stringResource(R.string.settings_overview_notifications_on)
}

private val AccountSettingsDestination.icon: ImageVector
    get() = when (this) {
        AccountSettingsDestination.ACCOUNT -> GradeyIcons.User
        AccountSettingsDestination.CONNECTED_SERVICES -> GradeyIcons.Link
        AccountSettingsDestination.NOTIFICATIONS -> GradeyIcons.Notification
        AccountSettingsDestination.PRIVACY_DATA -> GradeyIcons.SecurityLock
        AccountSettingsDestination.APP_PREFERENCES -> GradeyIcons.Settings
        AccountSettingsDestination.SUPPORT_ABOUT -> GradeyIcons.Information
    }

private enum class ProfileAvatarLoadState {
    INITIALS,
    LOADING,
    LOADED,
    FAILED,
}

@Composable
private fun ProfileAvatar(account: GradeyAccount) {
    val avatarUrl = normalizedProfileAvatarUrl(account.avatarURL)
    var loadState by remember(avatarUrl) {
        mutableStateOf(
            if (avatarUrl == null) ProfileAvatarLoadState.INITIALS else ProfileAvatarLoadState.LOADING,
        )
    }
    val initials = profileAvatarInitials(account.fullName, account.email)
    val accountLabel = account.fullName?.trim()?.takeIf(String::isNotEmpty)
        ?: account.email?.trim()?.takeIf(String::isNotEmpty)
        ?: stringResource(R.string.account_title)
    val avatarDescription = stringResource(
        if (loadState == ProfileAvatarLoadState.LOADED) {
            R.string.profile_avatar_photo_description
        } else {
            R.string.profile_avatar_initials_description
        },
        accountLabel,
    )

    Surface(
        modifier = Modifier
            .size(64.dp)
            .clearAndSetSemantics { contentDescription = avatarDescription },
        shape = CircleShape,
        color = MaterialTheme.colorScheme.primaryContainer,
        shadowElevation = 4.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = initials,
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            if (avatarUrl != null) {
                AsyncImage(
                    model = ImageRequest.Builder(LocalPlatformContext.current)
                        .data(avatarUrl)
                        .crossfade(true)
                        .build(),
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                    onLoading = { loadState = ProfileAvatarLoadState.LOADING },
                    onSuccess = { loadState = ProfileAvatarLoadState.LOADED },
                    onError = { loadState = ProfileAvatarLoadState.FAILED },
                )
            }
        }
    }
}

internal fun profileAvatarInitials(fullName: String?, email: String?): String {
    val nameInitials = fullName
        .orEmpty()
        .trim()
        .split(Regex("\\s+"))
        .asSequence()
        .filter(String::isNotBlank)
        .take(2)
        .mapNotNull { part -> part.firstOrNull()?.toString() }
        .joinToString("")
        .uppercase()

    return nameInitials.ifBlank {
        email
            ?.trim()
            ?.firstOrNull()
            ?.uppercase()
            ?: "G"
    }
}

internal fun normalizedProfileAvatarUrl(value: String?): String? {
    val candidate = value?.trim()?.takeIf(String::isNotEmpty) ?: return null
    val uri = runCatching { URI(candidate) }.getOrNull() ?: return null
    val scheme = uri.scheme?.lowercase()
    return candidate.takeIf {
        (scheme == "https" || scheme == "http") && !uri.host.isNullOrBlank()
    }
}

@Composable
private fun LinkedAccountStatus.localizedDisplayName(): String = stringResource(
    when (this) {
        LinkedAccountStatus.ACTIVE -> R.string.account_status_active
        LinkedAccountStatus.ACTION_REQUIRED -> R.string.account_status_action_required
        LinkedAccountStatus.PAUSED -> R.string.account_status_paused
        LinkedAccountStatus.LINKING -> R.string.account_status_linking
        LinkedAccountStatus.FAILED -> R.string.account_status_failed
    },
)

private fun NotificationLockScreenDetail.labelResource(): Int = when (this) {
    NotificationLockScreenDetail.PRIVATE_SUMMARY -> R.string.notifications_private_summary
    NotificationLockScreenDetail.MARK_AND_SUBJECT -> R.string.notifications_mark_and_subject
    NotificationLockScreenDetail.FULL_DETAILS -> R.string.notifications_full_details
}

@Composable
private fun SettingsSwitchRow(
    label: String,
    supportingText: String? = null,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(
                value = checked,
                enabled = enabled,
                role = Role.Switch,
                onValueChange = onCheckedChange,
            ),
        horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = label)
            supportingText?.let { supporting ->
                Text(
                    text = supporting,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        Switch(
            checked = checked,
            onCheckedChange = null,
            enabled = enabled,
        )
    }
}

@Composable
private fun SettingsRadioRow(
    label: String,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .selectable(
                selected = selected,
                enabled = enabled,
                role = Role.RadioButton,
                onClick = onClick,
            ),
        horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(
            selected = selected,
            onClick = null,
            enabled = enabled,
        )
        Text(
            text = label,
            modifier = Modifier.weight(1f),
        )
    }
}

private fun formatMinute(minuteOfDay: Int): String = String.format(
    Locale.getDefault(),
    "%02d:%02d",
    minuteOfDay.coerceIn(0, 1439) / 60,
    minuteOfDay.coerceIn(0, 1439) % 60,
)

internal const val ACCOUNT_LINKED_NOTIFICATIONS_TEST_TAG_PREFIX =
    "account-linked-notifications:"
internal const val ACCOUNT_FULL_NAME_FIELD_TEST_TAG = "account-full-name-field"
internal const val ACCOUNT_SAVE_FULL_NAME_TEST_TAG = "account-save-full-name"
internal const val ACCOUNT_DELETE_ENTRY_TEST_TAG = "account-delete-entry"

private fun formatSyncTimestamp(value: String): String = runCatching {
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .format(Instant.parse(value).atZone(ZoneId.systemDefault()))
}.getOrDefault(value)
