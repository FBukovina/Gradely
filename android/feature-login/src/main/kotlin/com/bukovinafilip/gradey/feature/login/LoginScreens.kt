package com.bukovinafilip.gradey.feature.login

import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.domain.SchoolDirectorySearch
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing

@Composable
fun SchoolLoginScreen(
    isLoading: Boolean,
    errorMessage: String? = null,
    directorySchools: List<SchoolDirectorySchool> = emptyList(),
    isDirectoryLoading: Boolean = false,
    directoryErrorMessage: String? = null,
    onLoadDirectory: () -> Unit = {},
    onRetryDirectory: () -> Unit = {},
    onLogin: (String, String, String) -> Unit,
    onBack: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    var school by remember { mutableStateOf("") }
    var schoolSearch by remember { mutableStateOf("") }
    var isSchoolSearchActive by remember { mutableStateOf(false) }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var isPasswordVisible by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val searchResults = remember(schoolSearch, directorySchools, isSchoolSearchActive) {
        if (isSchoolSearchActive) {
            SchoolDirectorySearch.results(schoolSearch, directorySchools)
        } else {
            emptyList()
        }
    }

    LaunchedEffect(Unit) { onLoadDirectory() }

    GradeyScreen(modifier = modifier.verticalScroll(rememberScrollState())) {
        if (onBack != null) {
            TextButton(onClick = onBack, enabled = !isLoading) { Text("Back") }
        }
        GradeyHero(
            title = "Connect Bakaláři",
            subtitle = "Sign in with the same school address, username, and password you use for Bakaláři.",
        )
        GradeySectionCard(title = "Bakaláři credentials") {
            Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = schoolSearch,
                    onValueChange = {
                        schoolSearch = it
                        isSchoolSearchActive = true
                    },
                    label = { Text("Find your school") },
                    placeholder = { Text("School name or town") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
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
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = school,
                    onValueChange = {
                        school = it
                        isSchoolSearchActive = false
                        schoolSearch = ""
                    },
                    label = { Text("School URL") },
                    placeholder = { Text("school.example.cz") },
                    leadingIcon = { Icon(Icons.Default.Link, contentDescription = null) },
                    singleLine = true,
                    enabled = !isLoading,
                )
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = username,
                    onValueChange = { username = it },
                    label = { Text("Username") },
                    singleLine = true,
                    enabled = !isLoading,
                )
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Password") },
                    singleLine = true,
                    visualTransformation = if (isPasswordVisible) {
                        VisualTransformation.None
                    } else {
                        PasswordVisualTransformation()
                    },
                    trailingIcon = {
                        IconButton(onClick = { isPasswordVisible = !isPasswordVisible }) {
                            Icon(
                                imageVector = if (isPasswordVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                contentDescription = if (isPasswordVisible) "Hide password" else "Show password",
                            )
                        }
                    },
                    enabled = !isLoading,
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
                    enabled = !isLoading && school.isNotBlank() && username.isNotBlank() && password.isNotEmpty(),
                    onClick = { onLogin(school, username, password) },
                ) {
                    Text(if (isLoading) "Connecting" else "Connect school")
                }
                Text(
                    "Your credentials are stored in Android encrypted storage and are used only to connect to your school server.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}
