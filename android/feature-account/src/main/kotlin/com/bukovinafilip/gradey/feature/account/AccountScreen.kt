package com.bukovinafilip.gradey.feature.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
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
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var notifications by remember { mutableStateOf(true) }

    GradeyScreen(modifier = modifier) {
        GradeyHero("Account", account?.fullName ?: "Gradey ID")
        GradeySectionCard(title = "Profile") {
            Icon(Icons.Default.Person, contentDescription = null)
            MetadataRow("Email", account?.email ?: "Demo")
            MetadataRow("Account ID", account?.id ?: "local-demo")
            Button(onClick = onSignOut) { Text("Sign out") }
        }
        GradeySectionCard(title = "Notifications") {
            Icon(Icons.Default.Notifications, contentDescription = null)
            MetadataRow("New marks", if (notifications) "Enabled" else "Disabled")
            Switch(checked = notifications, onCheckedChange = { notifications = it })
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
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

