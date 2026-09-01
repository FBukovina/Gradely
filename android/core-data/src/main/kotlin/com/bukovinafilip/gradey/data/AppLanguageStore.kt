package com.bukovinafilip.gradey.data

import android.content.Context
import android.content.ContextWrapper
import android.content.res.AssetManager
import android.content.res.Configuration
import android.content.res.Resources
import android.os.LocaleList
import com.bukovinafilip.gradey.model.AppLanguage
import java.util.Locale

class AppLanguageStore internal constructor(
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

    var selection: AppLanguage
        get() = AppLanguage.fromStorage(readValue())
        set(value) = writeValue(value.storageValue)

    fun localizedContext(context: Context, language: AppLanguage = selection): Context {
        val languageTag = language.languageTag ?: return context
        val locale = Locale.forLanguageTag(languageTag)
        val configuration = Configuration(context.resources.configuration).apply {
            setLocale(locale)
            setLocales(LocaleList(locale))
        }
        val configuredContext = context.createConfigurationContext(configuration)
        return LocalizedResourcesContext(
            base = context,
            localizedResources = configuredContext.resources,
            localizedAssets = configuredContext.assets,
        )
    }

    private companion object {
        const val PREFERENCES_NAME = "gradey-preferences"
        const val STORAGE_KEY = "settings.appLanguage"
    }
}

private class LocalizedResourcesContext(
    base: Context,
    private val localizedResources: Resources,
    private val localizedAssets: AssetManager,
) : ContextWrapper(base) {
    override fun getResources(): Resources = localizedResources

    override fun getAssets(): AssetManager = localizedAssets
}
