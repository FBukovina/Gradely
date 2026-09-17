package com.bukovinafilip.gradey.feature.gradeyai

import androidx.lifecycle.Lifecycle
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class GradeyAILifecyclePolicyTest {
    @Test
    fun `only started and resumed owners are foreground`() {
        assertThat(GradeyAILifecyclePolicy.isForeground(Lifecycle.State.DESTROYED)).isFalse()
        assertThat(GradeyAILifecyclePolicy.isForeground(Lifecycle.State.INITIALIZED)).isFalse()
        assertThat(GradeyAILifecyclePolicy.isForeground(Lifecycle.State.CREATED)).isFalse()
        assertThat(GradeyAILifecyclePolicy.isForeground(Lifecycle.State.STARTED)).isTrue()
        assertThat(GradeyAILifecyclePolicy.isForeground(Lifecycle.State.RESUMED)).isTrue()
    }
}
