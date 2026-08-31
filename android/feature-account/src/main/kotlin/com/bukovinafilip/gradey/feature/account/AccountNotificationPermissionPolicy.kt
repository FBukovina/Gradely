package com.bukovinafilip.gradey.feature.account

internal sealed interface NewMarksToggleAction {
    data class Persist(val enabled: Boolean) : NewMarksToggleAction

    data object RequestPermission : NewMarksToggleAction
}

internal fun resolveNewMarksToggleAction(
    requestedEnabled: Boolean,
    permissionGranted: Boolean,
): NewMarksToggleAction = when {
    !requestedEnabled -> NewMarksToggleAction.Persist(enabled = false)
    permissionGranted -> NewMarksToggleAction.Persist(enabled = true)
    else -> NewMarksToggleAction.RequestPermission
}
