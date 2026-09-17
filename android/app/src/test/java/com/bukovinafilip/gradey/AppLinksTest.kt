package com.bukovinafilip.gradey

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AppLinksTest {
    @Test
    fun `help center language follows Czech and defaults safely to English`() {
        assertThat(helpCenterLanguageCode("cs")).isEqualTo("cs")
        assertThat(helpCenterLanguageCode("CS")).isEqualTo("cs")
        assertThat(helpCenterLanguageCode("en")).isEqualTo("en")
        assertThat(helpCenterLanguageCode("de")).isEqualTo("en")
        assertThat(helpCenterLanguageCode(null)).isEqualTo("en")
    }

    @Test
    fun `privacy policy uses the resolved help center language`() {
        assertThat(privacyPolicyUrl("cs"))
            .isEqualTo("https://help.bukovinafilip.com/cs/articles/10-privacy-policy")
        assertThat(privacyPolicyUrl("en"))
            .isEqualTo("https://help.bukovinafilip.com/en/articles/10-privacy-policy")
    }
}
