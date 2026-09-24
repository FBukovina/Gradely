package com.bukovinafilip.gradey.navigation

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController

/**
 * The bounded signed-in graph. Authentication, age attestation, onboarding, and mandatory school
 * connection gates deliberately remain outside this host.
 */
@Composable
internal fun SignedInNavHost(
    todayContent: @Composable () -> Unit,
    subjectsContent: @Composable () -> Unit,
    absenceContent: @Composable () -> Unit,
    timetableContent: @Composable () -> Unit,
    mealsContent: @Composable () -> Unit,
    accountContent: @Composable () -> Unit,
    supportContent: @Composable () -> Unit,
    gradeyAiContent: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    navController: NavHostController = rememberNavController(),
) {
    NavHost(
        navController = navController,
        startDestination = MainDestination.TODAY.route,
        modifier = modifier,
    ) {
        composable(MainDestination.TODAY.route) { todayContent() }
        composable(MainDestination.SUBJECTS.route) { subjectsContent() }
        composable(MainDestination.ABSENCE.route) { absenceContent() }
        composable(MainDestination.TIMETABLE.route) { timetableContent() }
        composable(MainDestination.MEALS.route) { mealsContent() }
        composable(MainDestination.ACCOUNT.route) { accountContent() }
        composable(MainDestination.SUPPORT.route) { supportContent() }
        composable(MainDestination.GRADEY_AI.route) { gradeyAiContent() }
    }
}

/**
 * Selects a destination using tab semantics for primary roots and push semantics otherwise.
 */
internal fun NavHostController.navigateToMainDestination(destination: MainDestination) {
    if (destination.isPrimary) {
        navigateToPrimaryDestination(destination)
    } else {
        pushMainDestination(destination)
    }
}

private fun NavHostController.navigateToPrimaryDestination(destination: MainDestination) {
    require(destination.isPrimary) { "${destination.name} is not a primary destination" }

    // Account, Support, and Gradey AI are presentations above a primary root. Dismiss them without
    // saving them into a tab stack before selecting another primary destination.
    while (MainDestination.fromRoute(currentDestination?.route)?.isPrimary == false) {
        if (!popBackStack()) break
    }

    navigate(destination.route) {
        popUpTo(graph.findStartDestination().id) {
            saveState = true
        }
        launchSingleTop = true
        restoreState = true
    }
}

private fun NavHostController.pushMainDestination(destination: MainDestination) {
    require(!destination.isPrimary) { "${destination.name} is a primary destination" }
    navigate(destination.route) {
        launchSingleTop = true
    }
}

/** Replaces Gradey AI with Account so Back returns to the originating primary destination. */
internal fun NavHostController.navigateFromGradeyAiToAccount() {
    navigate(MainDestination.ACCOUNT.route) {
        popUpTo(MainDestination.GRADEY_AI.route) {
            inclusive = true
        }
        launchSingleTop = true
    }
}

/**
 * Replaces Gradey AI with Account -> Support, preserving the expected Support Back destination.
 */
internal fun NavHostController.navigateFromGradeyAiToSupport() {
    navigateFromGradeyAiToAccount()
    pushMainDestination(MainDestination.SUPPORT)
}

/**
 * Clears the active presentation and every saved tab stack, then creates a fresh Today root.
 * Use this after a school-account change or sign-out rather than retaining state from another user.
 */
internal fun NavHostController.resetToToday() {
    navigate(MainDestination.TODAY.route) {
        popUpTo(graph.id) {
            inclusive = false
            saveState = false
        }
        launchSingleTop = true
        restoreState = false
    }

    MainDestination.entries
        .asSequence()
        .filter { it != MainDestination.TODAY }
        .forEach { clearBackStack(it.route) }
}
