package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AgeAttestationKindTest {
    @Test
    fun `storage values match the iOS attestation record`() {
        assertThat(AgeAttestationKind.fromStorage("sixteenOrOlder"))
            .isEqualTo(AgeAttestationKind.SIXTEEN_OR_OLDER)
        assertThat(AgeAttestationKind.fromStorage("thirteenToFifteenWithParent"))
            .isEqualTo(AgeAttestationKind.THIRTEEN_TO_FIFTEEN_WITH_PARENT)
        assertThat(AgeAttestationKind.fromStorage("underThirteen"))
            .isEqualTo(AgeAttestationKind.UNDER_THIRTEEN)
        assertThat(AgeAttestationKind.fromStorage("unknown-future-value")).isNull()
    }

    @Test
    fun `under sixteen choices require parental consent`() {
        assertThat(AgeAttestationKind.SIXTEEN_OR_OLDER.needsParentalConsent).isFalse()
        assertThat(AgeAttestationKind.THIRTEEN_TO_FIFTEEN_WITH_PARENT.needsParentalConsent).isTrue()
        assertThat(AgeAttestationKind.UNDER_THIRTEEN.needsParentalConsent).isTrue()
        assertThat(AgeAttestationKind.entries.all(AgeAttestationKind::allowsAppUse)).isTrue()
    }
}
