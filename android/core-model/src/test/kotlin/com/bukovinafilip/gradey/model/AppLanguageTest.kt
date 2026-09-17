package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AppLanguageTest {
    @Test
    fun `storage values and locale tags match iOS`() {
        assertThat(AppLanguage.entries.map(AppLanguage::storageValue)).containsExactly(
            "system",
            "english",
            "englishChronicallyOnline",
            "czech",
            "czechChronicallyOnline",
        ).inOrder()
        assertThat(AppLanguage.entries.map(AppLanguage::languageTag)).containsExactly(
            null,
            "en",
            "en-CO",
            "cs",
            "cs-US",
        ).inOrder()
    }

    @Test
    fun `chronically online toggle preserves explicit language and resolves system language`() {
        assertThat(AppLanguage.ENGLISH.withChronicallyOnline(true, "cs"))
            .isEqualTo(AppLanguage.ENGLISH_CHRONICALLY_ONLINE)
        assertThat(AppLanguage.CZECH_CHRONICALLY_ONLINE.withChronicallyOnline(false, "en"))
            .isEqualTo(AppLanguage.CZECH)
        assertThat(AppLanguage.SYSTEM.withChronicallyOnline(true, "cs"))
            .isEqualTo(AppLanguage.CZECH_CHRONICALLY_ONLINE)
        assertThat(AppLanguage.SYSTEM.withChronicallyOnline(true, "de"))
            .isEqualTo(AppLanguage.ENGLISH_CHRONICALLY_ONLINE)
    }

    @Test
    fun `unknown persisted values fail safely to system language`() {
        assertThat(AppLanguage.fromStorage("english")).isEqualTo(AppLanguage.ENGLISH)
        assertThat(AppLanguage.fromStorage("future-language")).isEqualTo(AppLanguage.SYSTEM)
        assertThat(AppLanguage.fromStorage(null)).isEqualTo(AppLanguage.SYSTEM)
    }
}
