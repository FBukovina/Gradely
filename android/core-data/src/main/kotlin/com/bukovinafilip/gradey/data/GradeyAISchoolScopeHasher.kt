package com.bukovinafilip.gradey.data

import android.content.Context
import android.util.Base64
import com.bukovinafilip.gradey.model.StoredSession
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale

class GradeyAISchoolScopeHasher private constructor(
    private val salt: ByteArray,
) {
    constructor(context: Context) : this(loadOrCreateSalt(context.applicationContext))

    internal constructor(salt: ByteArray, copySalt: Boolean = true) : this(
        if (copySalt) salt.copyOf() else salt,
    )

    init {
        require(salt.isNotEmpty())
    }

    fun schoolScope(session: StoredSession): String {
        val host = session.baseURL
            .removePrefix("https://")
            .removePrefix("http://")
            .substringBefore('/')
            .lowercase(Locale.ROOT)
            .ifBlank { session.baseURL.lowercase(Locale.ROOT) }
        val studentIdentity = session.bakalari
            ?.username
            ?.trim()
            ?.lowercase(Locale.ROOT)
            ?.takeIf(String::isNotEmpty)
            ?: "default"
        val identity = listOf(
            session.cacheScope,
            "bakalari",
            host,
            studentIdentity,
        ).joinToString("\u001f")
        val digest = MessageDigest.getInstance("SHA-256").apply {
            update(salt)
            update(0)
            update(identity.toByteArray(StandardCharsets.UTF_8))
        }.digest()
        return "school_" + digest.joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
    }

    private companion object {
        const val PreferencesName = "gradey-ai-scope"
        const val SaltKey = "gradey.ai.schoolScopeSalt.v1"

        fun loadOrCreateSalt(context: Context): ByteArray {
            val preferences = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            preferences.getString(SaltKey, null)
                ?.let { runCatching { Base64.decode(it, Base64.NO_WRAP) }.getOrNull() }
                ?.takeIf { it.size >= 16 }
                ?.let { return it }

            val generated = ByteArray(32).also(SecureRandom()::nextBytes)
            preferences.edit()
                .putString(SaltKey, Base64.encodeToString(generated, Base64.NO_WRAP))
                .apply()
            return generated
        }
    }
}
