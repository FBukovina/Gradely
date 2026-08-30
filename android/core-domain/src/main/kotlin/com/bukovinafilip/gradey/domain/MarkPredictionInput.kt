package com.bukovinafilip.gradey.domain

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
}
