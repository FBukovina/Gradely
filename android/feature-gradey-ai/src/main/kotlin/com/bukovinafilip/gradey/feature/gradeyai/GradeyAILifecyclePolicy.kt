package com.bukovinafilip.gradey.feature.gradeyai

import androidx.lifecycle.Lifecycle

internal object GradeyAILifecyclePolicy {
    fun isForeground(state: Lifecycle.State): Boolean = state.isAtLeast(Lifecycle.State.STARTED)
}
