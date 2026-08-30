package com.bukovinafilip.gradey.ui

import android.content.res.Resources
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.model.AppLanguage

@Composable
fun AppLanguagePicker(
    selection: AppLanguage,
    onSelectionChange: (AppLanguage) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(GradeySpacing.sm),
    ) {
        LanguageOption(
            title = stringResource(R.string.language_system),
            subtitle = stringResource(R.string.language_system_subtitle),
            selected = selection == AppLanguage.SYSTEM,
            onClick = { onSelectionChange(AppLanguage.SYSTEM) },
        )
        LanguageOption(
            title = stringResource(R.string.language_english),
            subtitle = if (selection.isChronicallyOnline && selection.pickerLanguage == AppLanguage.ENGLISH) {
                stringResource(R.string.language_chronically_online_subtitle)
            } else {
                stringResource(R.string.language_standard_subtitle)
            },
            selected = selection.pickerLanguage == AppLanguage.ENGLISH,
            onClick = {
                onSelectionChange(
                    AppLanguage.ENGLISH.withChronicallyOnline(
                        enabled = selection.isChronicallyOnline,
                        systemLanguageCode = systemLanguageCode(),
                    ),
                )
            },
        )
        LanguageOption(
            title = stringResource(R.string.language_czech),
            subtitle = if (selection.isChronicallyOnline && selection.pickerLanguage == AppLanguage.CZECH) {
                stringResource(R.string.language_chronically_online_subtitle)
            } else {
                stringResource(R.string.language_standard_subtitle)
            },
            selected = selection.pickerLanguage == AppLanguage.CZECH,
            onClick = {
                onSelectionChange(
                    AppLanguage.CZECH.withChronicallyOnline(
                        enabled = selection.isChronicallyOnline,
                        systemLanguageCode = systemLanguageCode(),
                    ),
                )
            },
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = GradeySpacing.sm),
            horizontalArrangement = Arrangement.spacedBy(GradeySpacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.language_chronically_online_title),
                    style = MaterialTheme.typography.bodyLarge,
                )
                Text(
                    text = stringResource(R.string.language_chronically_online_subtitle),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Switch(
                checked = selection.isChronicallyOnline,
                onCheckedChange = { enabled ->
                    onSelectionChange(
                        selection.withChronicallyOnline(
                            enabled = enabled,
                            systemLanguageCode = systemLanguageCode(),
                        ),
                    )
                },
            )
        }
    }
}

@Composable
private fun LanguageOption(
    title: String,
    subtitle: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(role = Role.RadioButton, onClick = onClick)
            .padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(GradeySpacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                subtitle,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        RadioButton(selected = selected, onClick = null)
    }
}

private fun systemLanguageCode(): String =
    Resources.getSystem().configuration.locales[0]?.language.orEmpty()
