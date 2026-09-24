package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.Mark
import com.bukovinafilip.gradey.model.Subject
import java.text.Normalizer
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.round

enum class GradeBand {
    EXCELLENT,
    GOOD,
    AVERAGE,
    POOR,
    NEUTRAL,
}

enum class MarkWeightSource {
    EXPLICIT,
    INFERRED,
    FALLBACK,
}

data class ResolvedMarkWeight(
    val value: Double,
    val source: MarkWeightSource,
)

object GradeMath {
    private const val MaximumAverageInferenceGroups = 4
    private val MarkWeightRange = 1..10
    private const val AverageDisplayPrecision = 100.0

    fun parseMarkValue(markText: String): Double? = when (markText.trim()) {
        "1" -> 1.0
        "1+" -> 1.3
        "1-" -> 1.7
        "2" -> 2.0
        "2+" -> 2.3
        "2-" -> 2.7
        "3" -> 3.0
        "3+" -> 3.3
        "3-" -> 3.7
        "4" -> 4.0
        "4+" -> 4.3
        "4-" -> 4.7
        "5" -> 5.0
        "5+" -> 5.3
        "5-" -> 5.7
        else -> markText.replace(",", ".").toDoubleOrNull()
    }

    fun weightedAverage(marks: List<Mark>): Double? =
        weightedAverage(marks, resolvedWeights(marks))

    fun weightedAverage(marks: List<Mark>, subject: Subject): Double? =
        weightedAverage(marks, resolvedWeights(subject))

    fun subjectAverage(subject: Subject): Double? =
        parseAverageText(subject.averageText) ?: weightedAverage(subject.marks, resolvedWeights(subject))

    fun overallAverage(subjects: List<Subject>): Double? {
        val averages = subjects.mapNotNull(::subjectAverage)
        return averages.takeIf { it.isNotEmpty() }?.average()
    }

    fun theoreticalAverage(
        existingMarks: List<Mark>,
        subjectAverageText: String? = null,
        markValue: Double,
        weight: Int,
    ): Double {
        var totalWeight = max(1, weight).toDouble()
        var weightedSum = markValue * totalWeight
        val resolved = resolvedWeights(existingMarks, subjectAverageText)

        existingMarks.filter(::isLocallyGradableMark).forEach { mark ->
            val value = parseMarkValue(mark.markText) ?: return@forEach
            val markWeight = resolved[mark.id]?.value ?: 1.0
            totalWeight += markWeight
            weightedSum += value * markWeight
        }

        return weightedSum / totalWeight
    }

    fun resolvedWeight(mark: Mark, subject: Subject): ResolvedMarkWeight =
        resolvedWeights(subject)[mark.id] ?: defaultResolvedWeight(mark)

    fun resolvedWeights(subject: Subject): Map<String, ResolvedMarkWeight> =
        resolvedWeights(subject.marks, subject.averageText)

    fun resolvedWeights(
        marks: List<Mark>,
        matchingAverageText: String? = null,
    ): Map<String, ResolvedMarkWeight> {
        val resolved = marks.mapNotNull { mark ->
            explicitWeightValue(mark.weight)?.let { mark.id to ResolvedMarkWeight(it, MarkWeightSource.EXPLICIT) }
        }.toMap(mutableMapOf())

        marks.filter { isHiddenGradableMark(it) && it.id !in resolved }.forEach { mark ->
            val inferred = sameLabelExplicitWeight(mark, marks)
            if (inferred != null) resolved[mark.id] = ResolvedMarkWeight(inferred, MarkWeightSource.INFERRED)
        }

        val targetAverage = parseAverageText(matchingAverageText)
        if (targetAverage != null) {
            val inferredByLabel = averageInferredWeights(
                marks = marks,
                knownWeightsByID = resolved.mapValues { it.value.value },
                targetAverage = targetAverage,
            )
            marks.filter { isHiddenGradableMark(it) && it.id !in resolved }.forEach { mark ->
                val label = averageInferenceLabel(mark)
                val inferred = label?.let(inferredByLabel::get)
                if (inferred != null) {
                    resolved[mark.id] = ResolvedMarkWeight(inferred.toDouble(), MarkWeightSource.INFERRED)
                }
            }
        }

        return resolved
    }

    fun parseAverageText(averageText: String?): Double? = averageText
        ?.trim()
        ?.replace(",", ".")
        ?.replace(" ", "")
        ?.toDoubleOrNull()

    fun formattedAverage(average: Double?, locale: Locale = Locale.getDefault()): String =
        average?.let { String.format(locale, "%.2f", it) } ?: "-"

    fun formattedWeight(weight: Double): String =
        if (weight == round(weight)) weight.toInt().toString() else String.format(Locale.US, "%g", weight)

    fun band(average: Double?): GradeBand = when {
        average == null -> GradeBand.NEUTRAL
        average <= 1.5 -> GradeBand.EXCELLENT
        average <= 2.5 -> GradeBand.GOOD
        average <= 3.5 -> GradeBand.AVERAGE
        else -> GradeBand.POOR
    }

    fun band(mark: Mark): GradeBand = when {
        mark.isPoints -> GradeBand.EXCELLENT
        mark.markText.trim() in setOf("1", "1+", "1-") -> GradeBand.EXCELLENT
        mark.markText.trim() in setOf("2", "2+", "2-") -> GradeBand.GOOD
        mark.markText.trim() in setOf("3", "3+", "3-") -> GradeBand.AVERAGE
        mark.markText.trim() in setOf("4", "4+", "4-", "5", "5+", "5-") -> GradeBand.POOR
        else -> GradeBand.NEUTRAL
    }

    private fun weightedAverage(
        marks: List<Mark>,
        resolvedWeights: Map<String, ResolvedMarkWeight>,
    ): Double? {
        var totalWeight = 0.0
        var weightedSum = 0.0

        marks.filter(::isLocallyGradableMark).forEach { mark ->
            val value = parseMarkValue(mark.markText) ?: return@forEach
            val weight = resolvedWeights[mark.id]?.value ?: 1.0
            totalWeight += weight
            weightedSum += value * weight
        }

        return if (totalWeight > 0) weightedSum / totalWeight else null
    }

    private fun defaultResolvedWeight(mark: Mark): ResolvedMarkWeight =
        explicitWeightValue(mark.weight)?.let { ResolvedMarkWeight(it, MarkWeightSource.EXPLICIT) }
            ?: ResolvedMarkWeight(1.0, MarkWeightSource.FALLBACK)

    private fun explicitWeightValue(weight: Double?): Double? =
        weight?.let { max(0.0001, it) }

    private fun isHiddenGradableMark(mark: Mark): Boolean =
        mark.weight == null && isLocallyGradableMark(mark) && parseMarkValue(mark.markText) != null

    private fun isLocallyGradableMark(mark: Mark): Boolean =
        !mark.isPoints && mark.type != "unsupported"

    private fun sameLabelExplicitWeight(mark: Mark, marks: List<Mark>): Double? {
        val labelKind = MarkLabelKind.primaryKind(mark) ?: return null
        val label = labelKind.normalizedLabel(mark) ?: return null
        val matchingWeights = marks
            .filter { it.id != mark.id && !it.isPoints && labelKind.normalizedLabel(it) == label }
            .mapNotNull { explicitWeightValue(it.weight) }
            .toSet()
        return matchingWeights.singleOrNull()
    }

    private fun averageInferredWeights(
        marks: List<Mark>,
        knownWeightsByID: Map<String, Double>,
        targetAverage: Double,
    ): Map<String, Int> {
        val labels = orderedHiddenLabels(marks, knownWeightsByID)
        if (labels.isEmpty() || labels.size > MaximumAverageInferenceGroups) return emptyMap()

        val matches = mutableListOf<Map<String, Int>>()
        val candidate = mutableMapOf<String, Int>()

        fun search(labelIndex: Int) {
            if (matches.size > 1) return
            if (labelIndex == labels.size) {
                val average = weightedAverage(marks, knownWeightsByID, candidate)
                if (average != null && matchesDisplayedAverage(average, targetAverage)) {
                    matches += candidate.toMap()
                }
                return
            }

            val label = labels[labelIndex]
            MarkWeightRange.forEach { weight ->
                candidate[label] = weight
                search(labelIndex + 1)
            }
            candidate.remove(label)
        }

        search(0)
        return matches.singleOrNull().orEmpty()
    }

    private fun orderedHiddenLabels(marks: List<Mark>, knownWeightsByID: Map<String, Double>): List<String> {
        val seen = mutableSetOf<String>()
        return marks
            .filter { isHiddenGradableMark(it) && it.id !in knownWeightsByID }
            .mapNotNull(::averageInferenceLabel)
            .filter { seen.add(it) }
    }

    private fun weightedAverage(
        marks: List<Mark>,
        knownWeightsByID: Map<String, Double>,
        candidateWeightsByLabel: Map<String, Int>,
    ): Double? {
        var totalWeight = 0.0
        var weightedSum = 0.0

        marks.filter(::isLocallyGradableMark).forEach { mark ->
            val value = parseMarkValue(mark.markText) ?: return@forEach
            val weight = explicitWeightValue(mark.weight)
                ?: knownWeightsByID[mark.id]
                ?: averageInferenceLabel(mark)?.let(candidateWeightsByLabel::get)?.toDouble()
                ?: 1.0
            totalWeight += weight
            weightedSum += value * weight
        }

        return if (totalWeight > 0) weightedSum / totalWeight else null
    }

    private fun matchesDisplayedAverage(candidateAverage: Double, targetAverage: Double): Boolean =
        round(candidateAverage * AverageDisplayPrecision) == round(targetAverage * AverageDisplayPrecision)

    private fun averageInferenceLabel(mark: Mark): String? =
        MarkLabelKind.primaryKind(mark)?.normalizedLabel(mark)

    private enum class MarkLabelKind {
        TYPE_NOTE,
        TYPE,
        CAPTION;

        fun normalizedLabel(mark: Mark): String? = when (this) {
            TYPE_NOTE -> normalized(mark.typeNote)
            TYPE -> normalized(mark.type)
            CAPTION -> normalized(mark.caption)
        }

        companion object {
            fun primaryKind(mark: Mark): MarkLabelKind? = entries.firstOrNull { it.normalizedLabel(mark) != null }

            private fun normalized(value: String?): String? {
                val trimmed = value?.trim().orEmpty()
                if (trimmed.isBlank()) return null
                val folded = Normalizer
                    .normalize(trimmed, Normalizer.Form.NFD)
                    .replace("\\p{M}+".toRegex(), "")
                    .lowercase(Locale.forLanguageTag("cs-CZ"))
                    .split(Regex("\\s+"))
                    .filter { it.isNotBlank() }
                    .joinToString(" ")
                return folded.ifBlank { null }
            }
        }
    }
}
