package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class MarkPredictionInputTest {
    @Test
    fun `empty input is neutral while unparseable nonempty input is invalid`() {
        assertThat(MarkPredictionInput.markValue("")).isNull()
        assertThat(MarkPredictionInput.isInvalid("   ")).isFalse()
        assertThat(MarkPredictionInput.isInvalid("abc")).isTrue()
        assertThat(MarkPredictionInput.isInvalid("2+")).isFalse()
        assertThat(MarkPredictionInput.markValue("2+")).isWithin(0.0001).of(2.3)
    }

    @Test
    fun `mark text follows the iOS three-character limit`() {
        assertThat(MarkPredictionInput.acceptedMarkText("2+", "2+-")).isEqualTo("2+-")
        assertThat(MarkPredictionInput.acceptedMarkText("2+-", "1234")).isEqualTo("2+-")
    }

    @Test
    fun `weight controls are bounded from one through ten`() {
        assertThat(MarkPredictionInput.decreaseWeight(1)).isEqualTo(1)
        assertThat(MarkPredictionInput.decreaseWeight(2)).isEqualTo(1)
        assertThat(MarkPredictionInput.increaseWeight(9)).isEqualTo(10)
        assertThat(MarkPredictionInput.increaseWeight(10)).isEqualTo(10)
        assertThat(MarkPredictionInput.weightRange).containsExactlyElementsIn(1..10).inOrder()
    }
}
