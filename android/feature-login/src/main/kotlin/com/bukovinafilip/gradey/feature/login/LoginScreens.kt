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
    title: String = "Connect Bakaláři",
    subtitle: String = "Sign in with the same school address, username, and password you use for Bakaláři.",
    errorMessage: String? = null,
    directorySchools: List<SchoolDirectorySchool> = emptyList(),
    isDirectoryLoading: Boolean = false,
    directoryErrorMessage: String? = null,
    onLoadDirectory: () -> Unit = {},
    onRetryDirectory: () -> Unit = {},
    onLogin: (String, String, String) -> Unit,
    onCancelLogin: (() -> Unit)? = null,
    onInputChanged: () -> Unit = {},
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
            TextButton(onClick = onBack, enabled = !isLoading) { Text("Back") }
        }
        GradeyHero(
            title = title,
            subtitle = subtitle,
        )
        GradeySectionCard(title = "Bakaláři credentials") {
            Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = schoolSearch,
                    onValueChange = {
                        schoolSearch = it
                        isSchoolSearchActive = true
                        onInputChanged()
                    },
                    label = { Text("Find your school") },
                    placeholder = { Text("School name or town") },
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
                            Text("Retry")
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
                        "No matching school. You can enter its address below.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Text(
                    "Or enter the Bakaláři school address",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.labelMedium,
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
                    Text("Use demo account")
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
                    label = { Text("School URL") },
                    placeholder = { Text("school.example.cz") },
                    leadingIcon = { Icon(GradeyIcons.Link, contentDescription = null) },
                    singleLine = true,
                    enabled = !isLoading,
                    isError = hasAttemptedLogin && validation.schoolURLMessage != null,
                    supportingText = if (hasAttemptedLogin && validation.schoolURLMessage != null) {
                        { Text(validation.schoolURLMessage.orEmpty()) }
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
                    label = { Text("Username") },
                    singleLine = true,
                    enabled = !isLoading,
                    isError = hasAttemptedLogin && validation.usernameMessage != null,
                    supportingText = if (hasAttemptedLogin && validation.usernameMessage != null) {
                        { Text(validation.usernameMessage.orEmpty()) }
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
                    label = { Text("Password") },
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
                                contentDescription = if (isPasswordVisible) "Hide password" else "Show password",
                            )
                        }
                    },
                    enabled = !isLoading,
                    isError = hasAttemptedLogin && validation.passwordMessage != null,
                    supportingText = if (hasAttemptedLogin && validation.passwordMessage != null) {
                        { Text(validation.passwordMessage.orEmpty()) }
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
                            isLoading -> "Connecting…"
                            errorMessage != null -> "Try again"
                            else -> "Connect school"
                        },
                    )
                }
                if (isLoading && onCancelLogin != null) {
                    OutlinedButton(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = onCancelLogin,
                    ) {
                        Text("Cancel")
                    }
                }
                Text(
                    "Your credentials are stored in Android encrypted storage and are used only to connect to your school server.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}
