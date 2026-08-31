package com.bukovinafilip.gradey.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json

class SecureJsonStore private constructor(
    preferencesProvider: () -> SecureJsonPreferences,
    private val json: Json,
) {
    constructor(context: Context, fileName: String, json: Json) : this(
        preferencesProvider = {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            AndroidSecureJsonPreferences(
                EncryptedSharedPreferences.create(
                    context,
                    fileName,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                ),
            )
        },
        json = json,
    )

    internal constructor(preferences: SecureJsonPreferences, json: Json) : this(
        preferencesProvider = { preferences },
        json = json,
    )

    private val preferences: SecureJsonPreferences by lazy(preferencesProvider)

    fun <T> load(key: String, serializer: KSerializer<T>): T? {
        val encoded = preferences.getString(key, null) ?: return null
        return runCatching { json.decodeFromString(serializer, encoded) }.getOrNull()
    }

    fun <T> loadOrClearInvalid(key: String, serializer: KSerializer<T>): T? {
        return when (val result = read(key, serializer)) {
            SecureJsonReadResult.Absent -> null
            SecureJsonReadResult.Rejected -> {
                clear(key)
                null
            }
            is SecureJsonReadResult.Valid -> result.value
        }
    }

    internal fun <T> read(key: String, serializer: KSerializer<T>): SecureJsonReadResult<T> {
        val encoded = preferences.getString(key, null) ?: return SecureJsonReadResult.Absent
        return runCatching { json.decodeFromString(serializer, encoded) }
            .fold(
                onSuccess = { SecureJsonReadResult.Valid(it) },
                onFailure = { SecureJsonReadResult.Rejected },
            )
    }

    fun <T> save(key: String, value: T?, serializer: KSerializer<T>) {
        val encoded = value?.let { json.encodeToString(serializer, it) }
        commit(mapOf(key to encoded))
    }

    internal fun <T> saveReplacing(
        key: String,
        value: T,
        serializer: KSerializer<T>,
        removeKeys: Set<String>,
    ) {
        val changes = linkedMapOf<String, String?>()
        removeKeys.filterNot { it == key }.forEach { changes[it] = null }
        changes[key] = json.encodeToString(serializer, value)
        commit(changes)
    }

    fun clear(key: String) {
        commit(mapOf(key to null))
    }

    internal fun clear(keys: Set<String>) {
        if (keys.isEmpty()) return
        commit(keys.associateWith { null })
    }

    private fun commit(changes: Map<String, String?>) {
        check(preferences.commit(changes)) { "Failed to persist secure JSON values." }
    }
}

internal sealed interface SecureJsonReadResult<out T> {
    data object Absent : SecureJsonReadResult<Nothing>
    data object Rejected : SecureJsonReadResult<Nothing>
    data class Valid<T>(val value: T) : SecureJsonReadResult<T>
}

internal interface SecureJsonPreferences {
    fun getString(key: String, defaultValue: String?): String?
    fun commit(changes: Map<String, String?>): Boolean
}

private class AndroidSecureJsonPreferences(
    private val preferences: SharedPreferences,
) : SecureJsonPreferences {
    override fun getString(key: String, defaultValue: String?): String? =
        preferences.getString(key, defaultValue)

    override fun commit(changes: Map<String, String?>): Boolean =
        preferences.edit().apply {
            changes.forEach { (key, value) ->
                if (value == null) remove(key) else putString(key, value)
            }
        }.commit()
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
