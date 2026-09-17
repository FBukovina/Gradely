package com.bukovinafilip.gradey.model

enum class AppLanguage(val storageValue: String) {
    SYSTEM("system"),
    ENGLISH("english"),
    ENGLISH_CHRONICALLY_ONLINE("englishChronicallyOnline"),
    CZECH("czech"),
    CZECH_CHRONICALLY_ONLINE("czechChronicallyOnline");

    val languageTag: String?
        get() = when (this) {
            SYSTEM -> null
            ENGLISH -> "en"
            ENGLISH_CHRONICALLY_ONLINE -> "en-CO"
            CZECH -> "cs"
            CZECH_CHRONICALLY_ONLINE -> "cs-US"
        }

    val isChronicallyOnline: Boolean
        get() = this == ENGLISH_CHRONICALLY_ONLINE || this == CZECH_CHRONICALLY_ONLINE

    val pickerLanguage: AppLanguage
        get() = when (this) {
            SYSTEM -> SYSTEM
            ENGLISH, ENGLISH_CHRONICALLY_ONLINE -> ENGLISH
            CZECH, CZECH_CHRONICALLY_ONLINE -> CZECH
        }

    fun withChronicallyOnline(enabled: Boolean, systemLanguageCode: String): AppLanguage =
        when (pickerLanguage) {
            SYSTEM -> resolvedFromLanguageCode(systemLanguageCode).withChronicallyOnline(enabled, systemLanguageCode)
            ENGLISH -> if (enabled) ENGLISH_CHRONICALLY_ONLINE else ENGLISH
            CZECH -> if (enabled) CZECH_CHRONICALLY_ONLINE else CZECH
            ENGLISH_CHRONICALLY_ONLINE, CZECH_CHRONICALLY_ONLINE -> this
        }

    companion object {
        fun fromStorage(value: String?): AppLanguage =
            entries.firstOrNull { it.storageValue == value } ?: SYSTEM

        fun resolvedFromLanguageCode(languageCode: String?): AppLanguage =
            if (languageCode.equals("cs", ignoreCase = true)) CZECH else ENGLISH
    }
}
