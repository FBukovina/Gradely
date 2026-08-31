package com.bukovinafilip.gradey.feature.stravacz

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMealType
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZMenuDay
import com.bukovinafilip.gradey.model.StravaCZOrderType
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.ui.GradeyAuroraBackground
import com.bukovinafilip.gradey.ui.GradeyAuroraStyle
import com.bukovinafilip.gradey.ui.GradeyColors
import com.bukovinafilip.gradey.ui.GradeyIcons
import com.bukovinafilip.gradey.ui.GradeyHero
import com.bukovinafilip.gradey.ui.GradeyPrimaryButton
import com.bukovinafilip.gradey.ui.GradeyRadius
import com.bukovinafilip.gradey.ui.GradeySectionCard
import com.bukovinafilip.gradey.ui.GradeySpacing
import com.bukovinafilip.gradey.ui.MetadataRow
import com.bukovinafilip.gradey.ui.gradeyBrandGradient
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Currency
import java.util.Locale

internal const val STRAVACZ_CANTEEN_FIELD_TEST_TAG = "stravaCZCanteenField"
internal const val STRAVACZ_USERNAME_FIELD_TEST_TAG = "stravaCZUsernameField"
internal const val STRAVACZ_PASSWORD_FIELD_TEST_TAG = "stravaCZPasswordField"
internal const val STRAVACZ_PASSWORD_VISIBILITY_TEST_TAG = "stravaCZPasswordVisibility"
internal const val STRAVACZ_CONNECT_BUTTON_TEST_TAG = "stravaCZConnectButton"

@Composable
fun StravaCZScreen(
    session: StravaCZStoredSession?,
    menu: StravaCZMenu?,
    isLoading: Boolean,
    isRefreshing: Boolean,
    submittingMealID: Int?,
    errorMessage: String?,
    onConnect: (canteenNumber: String, username: String, password: String) -> Unit,
    onRefresh: () -> Unit,
    onSetMeal: (StravaCZMeal, Boolean) -> Unit,
    onDisconnect: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var pendingReplacement by remember { mutableStateOf<StravaCZMeal?>(null) }
    var pendingExistingMeal by remember { mutableStateOf<StravaCZMeal?>(null) }
    var showDisconnectConfirmation by rememberSaveable { mutableStateOf(false) }

    Box(modifier = modifier.fillMaxSize()) {
        GradeyAuroraBackground(
            style = if (session == null) {
                GradeyAuroraStyle.ACCOUNT_SETTINGS
            } else {
                GradeyAuroraStyle.STANDARD
            },
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding(),
        ) {
            MealsToolbar(
                connected = session != null,
                busy = isLoading || isRefreshing || submittingMealID != null,
                onRefresh = onRefresh,
                onDisconnect = { showDisconnectConfirmation = true },
                onOpenAccount = onOpenAccount,
                onOpenGradeyTools = onOpenGradeyTools,
            )

            when {
                session == null -> ConnectContent(
                    isLoading = isLoading,
                    errorMessage = errorMessage,
                    onConnect = onConnect,
                    modifier = Modifier.weight(1f),
                )
                menu == null -> FirstMenuLoad(
                    isLoading = isLoading,
                    errorMessage = errorMessage,
                    onRetry = onRefresh,
                    modifier = Modifier.weight(1f),
                )
                else -> MenuContent(
                    session = session,
                    menu = menu,
                    isRefreshing = isRefreshing,
                    submittingMealID = submittingMealID,
                    errorMessage = errorMessage,
                    onToggle = { meal ->
                        if (meal.ordered) {
                            onSetMeal(meal, false)
                        } else {
                            val existing = menu.days
                                .firstOrNull { it.date == meal.dateKey }
                                ?.orderedMainMeal
                            if (existing != null && existing.id != meal.id) {
                                pendingExistingMeal = existing
                                pendingReplacement = meal
                            } else {
                                onSetMeal(meal, true)
                            }
                        }
                    },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    val replacement = pendingReplacement
    val existing = pendingExistingMeal
    if (replacement != null && existing != null) {
        AlertDialog(
            onDismissRequest = {
                pendingReplacement = null
                pendingExistingMeal = null
            },
            title = { Text(stringResource(R.string.stravacz_replace_title)) },
            text = {
                Text(stringResource(R.string.stravacz_replace_message, existing.name, replacement.name))
            },
            confirmButton = {
                Button(
                    onClick = {
                        pendingReplacement = null
                        pendingExistingMeal = null
                        onSetMeal(replacement, true)
                    },
                ) { Text(stringResource(R.string.stravacz_replace_confirm)) }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        pendingReplacement = null
                        pendingExistingMeal = null
                    },
                ) { Text(stringResource(R.string.stravacz_cancel)) }
            },
        )
    }

    if (showDisconnectConfirmation) {
        AlertDialog(
            onDismissRequest = { showDisconnectConfirmation = false },
            title = { Text(stringResource(R.string.stravacz_disconnect_title)) },
            text = { Text(stringResource(R.string.stravacz_disconnect_message)) },
            confirmButton = {
                Button(
                    onClick = {
                        showDisconnectConfirmation = false
                        onDisconnect()
                    },
                ) { Text(stringResource(R.string.stravacz_confirm_disconnect)) }
            },
            dismissButton = {
                TextButton(onClick = { showDisconnectConfirmation = false }) {
                    Text(stringResource(R.string.stravacz_cancel))
                }
            },
        )
    }
}

@Composable
private fun MealsToolbar(
    connected: Boolean,
    busy: Boolean,
    onRefresh: () -> Unit,
    onDisconnect: () -> Unit,
    onOpenAccount: () -> Unit,
    onOpenGradeyTools: () -> Unit,
) {
    val refreshDescription = stringResource(R.string.stravacz_refresh)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(72.dp)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onOpenGradeyTools) {
            Icon(
                GradeyIcons.Sparkles,
                contentDescription = stringResource(R.string.stravacz_open_ai),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
        Text(
            stringResource(R.string.stravacz_title),
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onBackground,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        if (connected) {
            IconButton(
                onClick = onRefresh,
                enabled = !busy,
                modifier = Modifier.semantics { contentDescription = refreshDescription },
            ) {
                if (busy) {
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                } else {
                    Icon(
                        GradeyIcons.Refresh,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        } else {
            Spacer(Modifier.size(48.dp))
        }
        IconButton(onClick = onOpenAccount) {
            Icon(
                GradeyIcons.User,
                contentDescription = stringResource(R.string.stravacz_open_account),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
        if (connected) {
            IconButton(onClick = onDisconnect, enabled = !busy) {
                Icon(GradeyIcons.Cancel, contentDescription = stringResource(R.string.stravacz_disconnect), tint = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun ConnectContent(
    isLoading: Boolean,
    errorMessage: String?,
    onConnect: (String, String, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var canteenNumber by rememberSaveable { mutableStateOf("") }
    var username by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }
    val valid = canteenNumber.isNotBlank() && username.isNotBlank() && password.isNotEmpty()
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 120.dp),
        verticalArrangement = Arrangement.spacedBy(GradeySpacing.lg),
    ) {
        item {
            GradeyHero(
                title = stringResource(R.string.stravacz_connect_title),
                subtitle = stringResource(R.string.stravacz_connect_message),
            )
        }
        item {
            GradeySectionCard {
                OutlinedTextField(
                    value = canteenNumber,
                    onValueChange = { canteenNumber = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(STRAVACZ_CANTEEN_FIELD_TEST_TAG),
                    enabled = !isLoading,
                    singleLine = true,
                    label = { Text(stringResource(R.string.stravacz_canteen_number)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next),
                )
                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(STRAVACZ_USERNAME_FIELD_TEST_TAG),
                    enabled = !isLoading,
                    singleLine = true,
                    label = { Text(stringResource(R.string.stravacz_username)) },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag(STRAVACZ_PASSWORD_FIELD_TEST_TAG),
                    enabled = !isLoading,
                    singleLine = true,
                    label = { Text(stringResource(R.string.stravacz_password)) },
                    visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                    trailingIcon = {
                        IconButton(
                            onClick = { passwordVisible = !passwordVisible },
                            modifier = Modifier.testTag(STRAVACZ_PASSWORD_VISIBILITY_TEST_TAG),
                        ) {
                            Icon(
                                if (passwordVisible) GradeyIcons.ViewOff else GradeyIcons.View,
                                contentDescription = stringResource(
                                    if (passwordVisible) R.string.stravacz_hide_password else R.string.stravacz_show_password,
                                ),
                            )
                        }
                    },
                )
                ErrorText(errorMessage)
                GradeyPrimaryButton(
                    onClick = { onConnect(canteenNumber, username, password) },
                    modifier = Modifier.testTag(STRAVACZ_CONNECT_BUTTON_TEST_TAG),
                    enabled = valid && !isLoading,
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(Modifier.size(18.dp), color = GradeyColors.OnAccent, strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                    }
                    Text(stringResource(if (isLoading) R.string.stravacz_connecting else R.string.stravacz_connect))
                }
            }
        }
    }
}

@Composable
private fun FirstMenuLoad(
    isLoading: Boolean,
    errorMessage: String?,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        GradeySectionCard(modifier = Modifier.padding(24.dp)) {
            if (isLoading) {
                CircularProgressIndicator()
                Text(stringResource(R.string.stravacz_loading))
            } else {
                ErrorText(errorMessage ?: stringResource(R.string.stravacz_empty_message))
                Button(
                    onClick = onRetry,
                    modifier = Modifier.heightIn(min = 48.dp),
                ) {
                    Text(stringResource(R.string.stravacz_retry))
                }
            }
        }
    }
}

@Composable
private fun MenuContent(
    session: StravaCZStoredSession,
    menu: StravaCZMenu,
    isRefreshing: Boolean,
    submittingMealID: Int?,
    errorMessage: String?,
    onToggle: (StravaCZMeal) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 120.dp),
        verticalArrangement = Arrangement.spacedBy(GradeySpacing.md),
    ) {
        item { MealsHero(session, menu.orderedMeals.size) }
        if (isRefreshing) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.stravacz_refreshing), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (!errorMessage.isNullOrBlank()) {
            item {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = androidx.compose.foundation.shape.RoundedCornerShape(GradeyRadius.card),
                ) { ErrorText(errorMessage, Modifier.padding(16.dp)) }
            }
        }
        if (menu.days.isEmpty()) {
            item {
                GradeySectionCard(title = stringResource(R.string.stravacz_empty_title)) {
                    Text(stringResource(R.string.stravacz_empty_message), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } else {
            items(menu.days, key = StravaCZMenuDay::id) { day ->
                DayCard(day, submittingMealID, onToggle)
            }
        }
    }
}

@Composable
private fun MealsHero(session: StravaCZStoredSession, orderedCount: Int) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                gradeyBrandGradient(),
                androidx.compose.foundation.shape.RoundedCornerShape(GradeyRadius.card),
            )
            .padding(GradeySpacing.xl),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(GradeySpacing.md)) {
            Text(stringResource(R.string.stravacz_balance), color = GradeyColors.OnAccent.copy(alpha = 0.78f))
            Text(
                formattedBalance(session),
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold,
                color = GradeyColors.OnAccent,
            )
            HorizontalDivider(color = GradeyColors.OnAccent.copy(alpha = 0.22f))
            MetadataRowOnAccent(stringResource(R.string.stravacz_ordered), orderedCount.toString())
            MetadataRowOnAccent(
                stringResource(R.string.stravacz_canteen),
                session.canteenName?.takeIf(String::isNotBlank) ?: session.canteenNumber,
            )
        }
        Icon(
            GradeyIcons.Restaurant,
            contentDescription = null,
            modifier = Modifier.align(Alignment.TopEnd).size(32.dp),
            tint = GradeyColors.OnAccent.copy(alpha = 0.45f),
        )
    }
}

@Composable
private fun MetadataRowOnAccent(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = GradeyColors.OnAccent.copy(alpha = 0.76f))
        Text(
            value,
            modifier = Modifier.padding(start = 12.dp),
            color = GradeyColors.OnAccent,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun DayCard(
    day: StravaCZMenuDay,
    submittingMealID: Int?,
    onToggle: (StravaCZMeal) -> Unit,
) {
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(GradeyRadius.card),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
    ) {
        Column(Modifier.padding(GradeySpacing.lg)) {
            Text(
                formattedDay(day.date, locale),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            day.meals.forEachIndexed { index, meal ->
                if (index > 0) HorizontalDivider(Modifier.padding(vertical = 8.dp))
                MealRow(meal, submittingMealID == meal.id, onToggle)
            }
        }
    }
}

@Composable
private fun MealRow(meal: StravaCZMeal, isSubmitting: Boolean, onToggle: (StravaCZMeal) -> Unit) {
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                MealLabel(meal.localizedType())
                MealLabel(meal.localizedOrderType())
            }
            Text(meal.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(
                meal.formattedPrice(locale),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
            if (meal.allergenText.isNotBlank()) {
                Text(
                    stringResource(R.string.stravacz_allergens, meal.allergenText),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            meal.forbiddenAllergens?.takeIf(String::isNotBlank)?.let {
                Text(
                    stringResource(R.string.stravacz_forbidden_allergens, it),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        when {
            meal.canModify -> OutlinedButton(
                onClick = { onToggle(meal) },
                enabled = !isSubmitting,
                contentPadding = PaddingValues(horizontal = 12.dp),
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Icon(if (meal.ordered) GradeyIcons.Cancel else GradeyIcons.Tick, contentDescription = null)
                    Spacer(Modifier.width(5.dp))
                    Text(stringResource(if (meal.ordered) R.string.stravacz_cancel_order else R.string.stravacz_order))
                }
            }
            meal.ordered -> MealLabel(
                text = stringResource(R.string.stravacz_meal_ordered),
                leadingIcon = { Icon(GradeyIcons.Tick, contentDescription = null, modifier = Modifier.size(16.dp)) },
            )
            else -> Text(
                stringResource(R.string.stravacz_meal_read_only),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.labelMedium,
            )
        }
    }
}

@Composable
private fun MealLabel(
    text: String,
    leadingIcon: (@Composable () -> Unit)? = null,
) {
    Surface(
        shape = androidx.compose.foundation.shape.RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 9.dp, vertical = 5.dp),
            horizontalArrangement = Arrangement.spacedBy(5.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            leadingIcon?.invoke()
            Text(text, style = MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun StravaCZMeal.localizedType(): String = when (type) {
    StravaCZMealType.SOUP -> stringResource(R.string.stravacz_meal_type_soup)
    StravaCZMealType.MAIN -> stringResource(R.string.stravacz_meal_type_main)
    StravaCZMealType.UNKNOWN -> typeDescription.takeIf(String::isNotBlank)
        ?: stringResource(R.string.stravacz_meal_type_unknown)
}

@Composable
private fun StravaCZMeal.localizedOrderType(): String = when (orderType) {
    StravaCZOrderType.NORMAL -> stringResource(R.string.stravacz_order_type_normal)
    StravaCZOrderType.OPTIONAL -> stringResource(R.string.stravacz_order_type_optional)
    StravaCZOrderType.RESTRICTED -> stringResource(R.string.stravacz_order_type_restricted)
}

@Composable
private fun StravaCZMeal.formattedPrice(locale: Locale): String {
    if (price <= 0) return stringResource(R.string.stravacz_price_included)
    return NumberFormat.getCurrencyInstance(locale).apply { currency = Currency.getInstance("CZK") }.format(price)
}

@Composable
private fun formattedBalance(session: StravaCZStoredSession): String {
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    return "${NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 2
        maximumFractionDigits = 2
    }.format(session.balance)} ${session.currency}"
}

private fun formattedDay(value: String, locale: Locale): String = runCatching {
    LocalDate.parse(value).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale))
}.getOrDefault(value)

@Composable
private fun ErrorText(message: String?, modifier: Modifier = Modifier) {
    if (!message.isNullOrBlank()) {
        Text(message, modifier = modifier, color = MaterialTheme.colorScheme.error)
    }
}
