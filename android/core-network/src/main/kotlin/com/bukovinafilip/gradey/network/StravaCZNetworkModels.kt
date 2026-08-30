package com.bukovinafilip.gradey.network

import com.bukovinafilip.gradey.domain.StravaCZErrorKind
import com.bukovinafilip.gradey.domain.StravaCZException
import com.bukovinafilip.gradey.model.StravaCZAllergen
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMealType
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZMenuDay
import com.bukovinafilip.gradey.model.StravaCZOrderType
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import java.net.URI
import java.text.Normalizer
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle

object StravaCZResponseMapper {
    fun login(body: String, nowEpochMillis: Long = System.currentTimeMillis()): StravaCZStoredSession {
        val root = body.asObject()
        val user = root.objectValue("uzivatel")
        val sessionID = root.string("sid").orEmpty()
        val serviceURL = root.string("s5url").orEmpty()
        val canteenNumber = root.string("cislo").orEmpty()
        val username = root.string("jmeno").orEmpty()
        if (
            sessionID.isBlank() ||
            canteenNumber.isBlank() ||
            username.isBlank() ||
            !serviceURL.isSafeStravaServiceURL()
        ) {
            throw StravaCZException(
                StravaCZErrorKind.INVALID_RESPONSE,
                "Strava.cz returned an incomplete login response.",
            )
        }
        return StravaCZStoredSession(
            sessionID = sessionID,
            serviceURL = serviceURL,
            canteenNumber = canteenNumber,
            username = username,
            fullName = user.string("jmeno").orEmpty(),
            email = user.string("email"),
            balance = user.double("konto") ?: 0.0,
            currency = user.string("mena").orEmpty().ifBlank { "Kč" },
            canteenName = user.string("nazevJidelny"),
            savedAtEpochMillis = nowEpochMillis,
        )
    }

    fun menu(body: String): StravaCZMenu {
        val root = body.asObject()
        val meals = root.entries
            .asSequence()
            .filter { (key, _) -> key.startsWith("table") }
            .flatMap { (_, value) -> (value as? JsonArray).orEmpty().asSequence() }
            .mapNotNull(::meal)
            .toList()
        return StravaCZMenu(
            days = meals
                .groupBy(StravaCZMeal::dateKey)
                .map { (date, dayMeals) ->
                    val sorted = dayMeals.sortedWith(
                        compareBy<StravaCZMeal> { it.type.sortOrder }.thenBy(StravaCZMeal::id),
                    )
                    StravaCZMenuDay(
                        id = date,
                        title = date,
                        date = date,
                        ordered = sorted.any(StravaCZMeal::ordered),
                        meals = sorted,
                    )
                }
                .sortedBy(StravaCZMenuDay::date),
        )
    }

    fun balance(body: String): Double? = body.asObject().double("konto")

    private fun meal(element: JsonElement): StravaCZMeal? {
        val objectValue = element as? JsonObject ?: return null
        val name = objectValue.string("nazev").orEmpty().trim()
        val typeDescription = objectValue.string("druh_popis").orEmpty().trim()
        val longDescription = objectValue.string("delsiPopis").orEmpty().trim()
        val restriction = objectValue.objectValue("omezeniObj").string("den").orEmpty().trim()
        val allergens = (objectValue["alergeny"] as? JsonArray).orEmpty().mapNotNull(::allergen)
        val mealID = objectValue.int("veta") ?: return null
        val dateKey = normalizedDateKey(objectValue.string("datum").orEmpty()) ?: return null
        if (
            name.isEmpty() ||
            name.equals(typeDescription, ignoreCase = true) ||
            (longDescription.isEmpty() && allergens.isEmpty()) ||
            restriction.contains("VP")
        ) {
            return null
        }
        return StravaCZMeal(
            id = mealID,
            dateKey = dateKey,
            type = mealType(typeDescription),
            orderType = orderType(restriction),
            typeDescription = typeDescription,
            name = longDescription.ifEmpty { name },
            forbiddenAllergens = objectValue.string("zakazaneAlergeny"),
            allergens = allergens,
            ordered = (objectValue.int("pocet") ?: 0) > 0,
            price = objectValue.double("cena") ?: 0.0,
        )
    }

    private fun allergen(element: JsonElement): StravaCZAllergen? {
        val values = element as? JsonArray ?: return null
        val code = values.getOrNull(0).flexibleString().orEmpty()
        val name = values.getOrNull(1).flexibleString().orEmpty()
        if (code.isBlank() && name.isBlank()) return null
        return StravaCZAllergen(code = code, name = name)
    }

    private fun normalizedDateKey(rawValue: String): String? {
        val value = rawValue.trim()
        val formats = listOf("dd.MM.uuuu", "dd-MM-uuuu", "uuuu-MM-dd")
        return formats.firstNotNullOfOrNull { pattern ->
            runCatching {
                LocalDate.parse(
                    value,
                    DateTimeFormatter.ofPattern(pattern).withResolverStyle(ResolverStyle.STRICT),
                ).toString()
            }.getOrNull()
        }
    }

    private fun mealType(value: String): StravaCZMealType {
        val folded = value.folded()
        return when {
            "polevka" in folded -> StravaCZMealType.SOUP
            "obed" in folded -> StravaCZMealType.MAIN
            else -> StravaCZMealType.UNKNOWN
        }
    }

    private fun orderType(restriction: String): StravaCZOrderType = when {
        "CO" in restriction -> StravaCZOrderType.RESTRICTED
        "T" in restriction -> StravaCZOrderType.OPTIONAL
        else -> StravaCZOrderType.NORMAL
    }

    private val StravaCZMealType.sortOrder: Int
        get() = when (this) {
            StravaCZMealType.SOUP -> 0
            StravaCZMealType.MAIN -> 1
            StravaCZMealType.UNKNOWN -> 2
        }

    private fun String.folded(): String = Normalizer.normalize(lowercase(), Normalizer.Form.NFD)
        .replace("\\p{M}+".toRegex(), "")

    private fun String.isSafeStravaServiceURL(): Boolean = runCatching {
        val uri = URI(this)
        uri.scheme.equals("https", ignoreCase = true) &&
            uri.userInfo == null &&
            uri.host?.lowercase()?.let { it == "strava.cz" || it.endsWith(".strava.cz") } == true
    }.getOrDefault(false)
}

private fun String.asObject(): JsonObject = try {
    GradeyJson.parseToJsonElement(this).jsonObject
} catch (error: Throwable) {
    throw StravaCZException(
        StravaCZErrorKind.DECODING,
        "Strava.cz returned data Gradey could not read.",
        cause = error,
    )
}

private fun JsonObject?.objectValue(key: String): JsonObject = this?.get(key) as? JsonObject ?: JsonObject(emptyMap())

private fun JsonObject?.string(key: String): String? = this?.get(key).flexibleString()?.trim()?.takeIf(String::isNotEmpty)

private fun JsonObject?.int(key: String): Int? {
    val primitive = this?.get(key) as? JsonPrimitive ?: return null
    return primitive.intOrNull ?: primitive.contentOrNull?.trim()?.toIntOrNull()
}

private fun JsonObject?.double(key: String): Double? {
    val primitive = this?.get(key) as? JsonPrimitive ?: return null
    return primitive.doubleOrNull ?: primitive.contentOrNull
        ?.trim()
        ?.replace(',', '.')
        ?.toDoubleOrNull()
}

private fun JsonElement?.flexibleString(): String? {
    val primitive = this as? JsonPrimitive ?: return null
    return primitive.contentOrNull ?: primitive.booleanOrNull?.toString()
}
