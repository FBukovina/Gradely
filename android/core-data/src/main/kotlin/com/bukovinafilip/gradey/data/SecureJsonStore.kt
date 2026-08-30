package com.bukovinafilip.gradey.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json

class SecureJsonStore(
    context: Context,
    fileName: String,
    private val json: Json,
) {
    private val preferences: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        EncryptedSharedPreferences.create(
            context,
            fileName,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun <T> load(key: String, serializer: KSerializer<T>): T? {
        val encoded = preferences.getString(key, null) ?: return null
        return runCatching { json.decodeFromString(serializer, encoded) }.getOrNull()
    }

    fun <T> loadOrClearInvalid(key: String, serializer: KSerializer<T>): T? {
        val encoded = preferences.getString(key, null)
        return decodeStoredValueOrClear(encoded, serializer, json) {
            preferences.edit().remove(key).apply()
        }
    }

    fun <T> save(key: String, value: T?, serializer: KSerializer<T>) {
        preferences.edit().apply {
            if (value == null) remove(key) else putString(key, json.encodeToString(serializer, value))
        }.apply()
    }

    fun clear(key: String) {
        preferences.edit().remove(key).apply()
    }
}

internal fun <T> decodeStoredValueOrClear(
    encoded: String?,
    serializer: KSerializer<T>,
    json: Json,
    clear: () -> Unit,
): T? {
    if (encoded == null) return null
    return runCatching { json.decodeFromString(serializer, encoded) }
        .getOrElse {
            clear()
            null
        }
}
