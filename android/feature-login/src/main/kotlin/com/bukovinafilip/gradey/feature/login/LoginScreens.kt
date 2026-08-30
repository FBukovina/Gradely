package com.bukovinafilip.gradey.feature.login

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyScreen
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing

@Composable
fun SchoolLoginScreen(
    isLoading: Boolean,
    onLogin: (SchoolProvider, String, String, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var provider by remember { mutableStateOf(SchoolProvider.BAKALARI) }
    var school by remember { mutableStateOf("demo.gradey.app") }
    var username by remember { mutableStateOf("apple-review") }
    var password by remember { mutableStateOf("GradelyDemo2026!") }

    GradeyScreen(modifier = modifier) {
        GradeyHero(
            title = "Link school",
            subtitle = "Connect Bakalari or EduPage and keep your marks, absences, and timetable cached for offline use.",
        )
        GradeySectionCard(title = "Provider") {
            Row(horizontalArrangement = Arrangement.spacedBy(GradeySpacing.sm)) {
                SchoolProvider.entries.forEach { candidate ->
                    FilterChip(
                        selected = provider == candidate,
                        onClick = { provider = candidate },
                        label = { Text(candidate.displayName) },
                    )
                }
            }
        }
        GradeySectionCard(title = "Credentials") {
            Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = school,
                    onValueChange = { school = it },
                    label = { Text(if (provider == SchoolProvider.EDU_PAGE) "EduPage school" else "School URL") },
                    singleLine = true,
                )
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = username,
                    onValueChange = { username = it },
                    label = { Text("Username") },
                    singleLine = true,
                )
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(),
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Password") },
                    singleLine = true,
                )
                Button(
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                    onClick = { onLogin(provider, school, username, password) },
                ) {
                    Icon(Icons.Default.Link, contentDescription = null)
                    Text(if (isLoading) "Connecting" else "Connect school")
                }
                Text("For EduPage, two-factor and child selection are modeled as explicit follow-up steps in the repository API.", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

