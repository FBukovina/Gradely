package com.bukovinafilip.gradey.data

import android.content.Context
import java.security.MessageDigest

class PushRegistrationStore internal constructor(
    private val readIdentity: () -> String?,
    private val writeIdentity: (String?) -> Unit,
) {
    constructor(context: Context) : this(
        readIdentity = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getString(IDENTITY_KEY, null)
        },
        writeIdentity = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .apply {
                    if (value == null) remove(IDENTITY_KEY) else putString(IDENTITY_KEY, value)
                }
                .apply()
        },
    )

    fun needsRegistration(token: String, accountID: String, environment: String): Boolean =
        readIdentity() != identity(token, accountID, environment)

    fun markRegistered(token: String, accountID: String, environment: String) {
        writeIdentity(identity(token, accountID, environment))
    }

    fun clear() = writeIdentity(null)

    private fun identity(token: String, accountID: String, environment: String): String {
        val tokenHash = MessageDigest.getInstance("SHA-256")
            .digest(token.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        return "${accountID.trim()}|${environment.trim()}|$tokenHash"
    }

    private companion object {
        const val PREFERENCES_NAME = "gradey-preferences"
        const val IDENTITY_KEY = "push.registration.identity.v1"
    }
}
