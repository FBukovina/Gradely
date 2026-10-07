package com.bukovinafilip.gradey.feature.account

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AccountAvatarTest {
    @Test
    fun `uses the first two name initials`() {
        assertThat(profileAvatarInitials("Filip Jan Bukovina", "ignored@example.com"))
            .isEqualTo("FJ")
    }

    @Test
    fun `normalizes whitespace and preserves localized initials`() {
        assertThat(profileAvatarInitials("  řeka   černá  ", null))
            .isEqualTo("ŘČ")
    }

    @Test
    fun `falls back to email initial when name is blank`() {
        assertThat(profileAvatarInitials("   ", " student@example.com"))
            .isEqualTo("S")
    }

    @Test
    fun `uses Gradey initial when account has no display identity`() {
        assertThat(profileAvatarInitials(null, null)).isEqualTo("G")
    }

    @Test
    fun `accepts trimmed web avatar URLs`() {
        assertThat(normalizedProfileAvatarUrl("  https://images.example/avatar.png  "))
            .isEqualTo("https://images.example/avatar.png")
    }

    @Test
    fun `rejects non-web and malformed avatar URLs`() {
        assertThat(normalizedProfileAvatarUrl("file:///private/avatar.png")).isNull()
        assertThat(normalizedProfileAvatarUrl("https:avatar.png")).isNull()
        assertThat(normalizedProfileAvatarUrl("not a URL")).isNull()
    }
}
