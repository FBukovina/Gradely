package com.bukovinafilip.gradey.data

import android.content.Context
import com.bukovinafilip.gradey.model.AgeAttestationKind

class AgeAttestationStore internal constructor(
    private val readValue: () -> String?,
    private val writeValue: (String) -> Unit,
) {
    constructor(context: Context) : this(
        readValue = {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getString(STORAGE_KEY, null)
        },
        writeValue = { value ->
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(STORAGE_KEY, value)
                .apply()
        },
    )

    val kind: AgeAttestationKind?
        get() = AgeAttestationKind.fromStorage(readValue())

    val allowsAppUse: Boolean
        get() = kind?.allowsAppUse == true

    fun confirm(kind: AgeAttestationKind) {
        writeValue(kind.storageValue)
    }

    private companion object {
        const val PREFERENCES_NAME = "gradey-preferences"
        const val STORAGE_KEY = "gradey.ageAttestation.v1"
    }
}
