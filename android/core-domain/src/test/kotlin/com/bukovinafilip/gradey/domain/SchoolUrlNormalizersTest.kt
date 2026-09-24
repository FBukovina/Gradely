package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SchoolUrlNormalizersTest {
    @Test
    fun bakalariNormalizerAddsHttpsAndRemovesLoginPath() {
        assertThat(SchoolURLNormalizer.normalizedBaseURL("demo.bakalari.cz/login"))
            .isEqualTo("https://demo.bakalari.cz")
    }
}
