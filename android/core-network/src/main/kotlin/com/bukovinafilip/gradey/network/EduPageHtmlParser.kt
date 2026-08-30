package com.bukovinafilip.gradey.network

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.jsoup.Jsoup

object EduPageHtmlParser {
    fun firstJSONObject(text: String, containingKey: String): JsonObject? {
        var index = 0
        while (index < text.length) {
            val start = text.indexOf("{", index)
            if (start == -1) return null
            val jsonText = balancedJSONObject(text, start)
            if (jsonText != null && jsonText.contains("\"$containingKey\"")) {
                val parsed = runCatching { GradeyJson.parseToJsonElement(jsonText).jsonObject }.getOrNull()
                if (parsed?.containsKey(containingKey) == true) return parsed
            }
            index = start + 1
        }
        return null
    }

    fun firstCapture(text: String, prefixes: List<String>): String? =
        prefixes.firstNotNullOfOrNull { prefix ->
            val start = text.indexOf(prefix)
            if (start == -1) null else text.substring(start + prefix.length).substringBefore("\"").takeIf { it.isNotBlank() }
        }

    fun documentTitle(html: String): String =
        Jsoup.parse(html).title()

    private fun balancedJSONObject(text: String, start: Int): String? {
        var depth = 0
        var inString = false
        var escaped = false
        for (index in start until text.length) {
            when (val char = text[index]) {
                '\\' -> if (inString) escaped = !escaped
                '"' -> if (!escaped) inString = !inString else escaped = false
                '{' -> if (!inString) depth += 1 else escaped = false
                '}' -> if (!inString) {
                    depth -= 1
                    if (depth == 0) return text.substring(start, index + 1)
                } else {
                    escaped = false
                }
                else -> escaped = false
            }
        }
        return null
    }
}

