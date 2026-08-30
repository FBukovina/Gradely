package com.bukovinafilip.gradey.domain

import kotlin.math.abs

enum class MarkPredictionComparison {
    BETTER,
    SAME,
    WORSE,
    UNKNOWN,
}

object MarkPredictionInput {
    const val maxMarkLength = 3
    val weightRange = 1..10

    fun acceptedMarkText(current: String, candidate: String): String =
        if (candidate.length <= maxMarkLength) candidate else current

    fun markValue(markText: String): Double? =
        markText.takeIf(String::isNotBlank)?.let(GradeMath::parseMarkValue)

    fun isInvalid(markText: String): Boolean = markText.isNotBlank() && markValue(markText) == null

    fun decreaseWeight(weight: Int): Int = (weight - 1).coerceIn(weightRange)

    fun increaseWeight(weight: Int): Int = (weight + 1).coerceIn(weightRange)

    fun comparison(currentAverage: Double?, predictedAverage: Double?): MarkPredictionComparison {
        if (currentAverage == null || predictedAverage == null) return MarkPredictionComparison.UNKNOWN
        val difference = predictedAverage - currentAverage
        return when {
            abs(difference) <= 0.010000001 -> MarkPredictionComparison.SAME
            difference < 0 -> MarkPredictionComparison.BETTER
            else -> MarkPredictionComparison.WORSE
        }
    }
}
