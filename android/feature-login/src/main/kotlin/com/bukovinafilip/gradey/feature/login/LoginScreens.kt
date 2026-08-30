package com.bukovinafilip.gradey.feature.login

import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.domain.BakalariDemoAccount
import com.bukovinafilip.gradey.domain.SchoolDirectorySearch
import com.bukovinafilip.gradey.domain.SchoolLoginValidator
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.bukovinafilip.gradey.ui.GradeyIcons
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing

@Composable
fun SchoolLoginScreen(
    isLoading: Boolean,
    initialSchoolURL: String = "",
    title: String? = null,
    subtitle: String? = null,
    errorMessage: String? = null,
    directorySchools: List<SchoolDirectorySchool> = emptyList(),
    isDirectoryLoading: Boolean = false,
    directoryErrorMessage: String? = null,
    onLoadDirectory: () -> Unit = {},
    onRetryDirectory: () -> Unit = {},
    onLogin: (String, String, String) -> Unit,
    onCancelLogin: (() -> Unit)? = null,
    onInputChanged: () -> Unit = {},
    onOpenHelp: () -> Unit = {},
    onOpenGitHub: () -> Unit = {},
    onBack: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    var school by remember(initialSchoolURL) { mutableStateOf(initialSchoolURL) }
    var schoolSearch by remember { mutableStateOf("") }
    var isSchoolSearchActive by remember { mutableStateOf(false) }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var isPasswordVisible by remember { mutableStateOf(false) }
    var hasAttemptedLogin by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val resolvedTitle = title ?: stringResource(R.string.login_title)
    val resolvedSubtitle = subtitle ?: stringResource(R.string.login_subtitle)
    val validation = remember(school, username, password) {
        SchoolLoginValidator.validate(school, username, password)
    }
    val searchResults = remember(schoolSearch, directorySchools, isSchoolSearchActive) {
        if (isSchoolSearchActive) {
            SchoolDirectorySearch.results(schoolSearch, directorySchools)
        } else {
            emptyList()
        }
    }

    LaunchedEffect(Unit) { onLoadDirectory() }

    fun submitLogin() {
        hasAttemptedLogin = true
        if (!validation.isValid || isLoading) return
        focusManager.clearFocus()
        onLogin(school, username, password)
    }

    GradeyScreen(modifier = modifier.verticalScroll(rememberScrollState())) {
        if (onBack != null) {
            TextButton(onClick = onBack, enabled = !isLoading) {
                Text(stringResource(R.string.login_back))
            }
        }
        GradeyHero(
            title = resolvedTitle,
            subtitle = resolvedSubtitle,
        )
        GradeySectionCard(title = stringResource(R.string.login_credentials_title)) {
            Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = schoolSearch,
                    onValueChange = {
                        schoolSearch = it
                        isSchoolSearchActive = true
                        onInputChanged()
                    },
                    label = { Text(stringResource(R.string.login_find_school)) },
                    placeholder = { Text(stringResource(R.string.login_school_search_placeholder)) },
                    leadingIcon = { Icon(GradeyIcons.Search, contentDescription = null) },
                    trailingIcon = {
                        if (isDirectoryLoading) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        }
                    },
                    singleLine = true,
                    enabled = !isLoading,
                )
                if (!directoryErrorMessage.isNullOrBlank()) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = directoryErrorMessage,
                            modifier = Modifier.weight(1f),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )
                        TextButton(onClick = onRetryDirectory, enabled = !isDirectoryLoading) {
                            Text(stringResource(R.string.login_retry))
                        }
                    }
                }
                if (searchResults.isNotEmpty()) {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = MaterialTheme.shapes.medium,
                        color = MaterialTheme.colorScheme.surfaceContainer,
                    ) {
                        LazyColumn(modifier = Modifier.heightIn(max = 320.dp)) {
                            items(searchResults, key = SchoolDirectorySchool::id) { result ->
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable(enabled = !isLoading) {
                                            schoolSearch = result.trimmedName
                                            school = result.trimmedSchoolURL
                                            isSchoolSearchActive = false
                                            hasAttemptedLogin = false
                                            onInputChanged()
                                            focusManager.clearFocus()
                                        }
                                        .padding(horizontal = GradeySpacing.md, vertical = GradeySpacing.sm),
                                ) {
                                    Text(result.trimmedName, style = MaterialTheme.typography.titleSmall)
                                    Text(
                                        text = listOf(result.trimmedTown, result.trimmedSchoolURL)
                                            .filter(String::isNotBlank)
                                            .joinToString(" · "),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                                HorizontalDivider()
                            }
                        }
                    }
                } else if (
                    isSchoolSearchActive &&
                    schoolSearch.isNotBlank() &&
                    directorySchools.isNotEmpty() &&
                    !isDirectoryLoading &&
                    directoryErrorMessage == null
                ) {
                    Text(
                        stringResource(R.string.login_no_matching_school),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Text(
                    stringResource(R.string.login_manual_address_prompt),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.labelMedium,
                )
                Text(
                    stringResource(R.string.login_manual_address_steps),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
                Text(
                    stringResource(R.string.login_manual_address_example),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
                OutlinedButton(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                    onClick = {
                        school = BakalariDemoAccount.schoolURL
                        schoolSearch = ""
                        username = BakalariDemoAccount.username
                        password = BakalariDemoAccount.password
                        isSchoolSearchActive = false
                        hasAttemptedLogin = false
                        onInputChanged()
                        focusManager.clearFocus()
                    },
                ) {
                    Text(stringResource(R.string.login_use_demo_account))
                }
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = school,
                    onValueChange = {
                        school = it
                        isSchoolSearchActive = false
                        schoolSearch = ""
                        onInputChanged()
                    },
                    label = { Text(stringResource(R.string.login_school_url)) },
                    placeholder = { Text(stringResource(R.string.login_school_url_placeholder)) },
                    leadingIcon = { Icon(GradeyIcons.Link, contentDescription = null) },
                    singleLine = true,
                    enabled = !isLoading,
                    isError = hasAttemptedLogin && validation.schoolURLMessage != null,
                    supportingText = if (hasAttemptedLogin && validation.schoolURLMessage != null) {
                        {
                            Text(
                                stringResource(
                                    if (school.isBlank()) {
                                        R.string.login_school_url_required
                                    } else {
                                        R.string.login_school_url_invalid
                                    },
                                ),
                            )
                        }
                    } else {
                        null
                    },
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        keyboardType = KeyboardType.Uri,
                        imeAction = ImeAction.Next,
                    ),
                    keyboardActions = KeyboardActions(
                        onNext = { focusManager.moveFocus(FocusDirection.Down) },
                    ),
                )
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = username,
                    onValueChange = {
                        username = it
                        onInputChanged()
                    },
                    label = { Text(stringResource(R.string.login_username)) },
                    singleLine = true,
                    enabled = !isLoading,
                    isError = hasAttemptedLogin && validation.usernameMessage != null,
                    supportingText = if (hasAttemptedLogin && validation.usernameMessage != null) {
                        { Text(stringResource(R.string.login_username_required)) }
                    } else {
                        null
                    },
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        keyboardType = KeyboardType.Text,
                        imeAction = ImeAction.Next,
                    ),
                    keyboardActions = KeyboardActions(
                        onNext = { focusManager.moveFocus(FocusDirection.Down) },
                    ),
                )
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = password,
                    onValueChange = {
                        password = it
                        onInputChanged()
                    },
                    label = { Text(stringResource(R.string.login_password)) },
                    singleLine = true,
                    visualTransformation = if (isPasswordVisible) {
                        VisualTransformation.None
                    } else {
                        PasswordVisualTransformation()
                    },
                    trailingIcon = {
                        IconButton(
                            enabled = !isLoading,
                            onClick = { isPasswordVisible = !isPasswordVisible },
                        ) {
                            Icon(
                                imageVector = if (isPasswordVisible) GradeyIcons.ViewOff else GradeyIcons.View,
                                contentDescription = stringResource(
                                    if (isPasswordVisible) {
                                        R.string.login_hide_password
                                    } else {
                                        R.string.login_show_password
                                    },
                                ),
                            )
                        }
                    },
                    enabled = !isLoading,
                    isError = hasAttemptedLogin && validation.passwordMessage != null,
                    supportingText = if (hasAttemptedLogin && validation.passwordMessage != null) {
                        { Text(stringResource(R.string.login_password_required)) }
                    } else {
                        null
                    },
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        keyboardType = KeyboardType.Password,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(onDone = { submitLogin() }),
                )
                if (!errorMessage.isNullOrBlank()) {
                    Text(
                        text = errorMessage,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                    onClick = ::submitLogin,
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                        )
                    }
                    Text(
                        when {
                            isLoading -> stringResource(R.string.login_connecting)
                            errorMessage != null -> stringResource(R.string.login_try_again)
                            else -> stringResource(R.string.login_connect_school)
                        },
                    )
                }
                if (isLoading && onCancelLogin != null) {
                    OutlinedButton(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = onCancelLogin,
                    ) {
                        Text(stringResource(R.string.login_cancel))
                    }
                }
                Text(
                    stringResource(R.string.login_credentials_privacy),
                    style = MaterialTheme.typography.bodySmall,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
                    TextButton(onClick = onOpenHelp) {
                        Text(stringResource(R.string.login_help))
                    }
                    TextButton(onClick = onOpenGitHub) {
                        Text(stringResource(R.string.login_github))
                    }
                }
            }
        }
    }
}
