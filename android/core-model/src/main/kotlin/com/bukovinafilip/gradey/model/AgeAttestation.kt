package com.bukovinafilip.gradey.model

enum class AgeAttestationKind(
    val storageValue: String,
    val needsParentalConsent: Boolean,
) {
    SIXTEEN_OR_OLDER("sixteenOrOlder", false),
    THIRTEEN_TO_FIFTEEN_WITH_PARENT("thirteenToFifteenWithParent", true),
    UNDER_THIRTEEN("underThirteen", true),
    ;

    val allowsAppUse: Boolean get() = true

    companion object {
        fun fromStorage(value: String?): AgeAttestationKind? =
            entries.firstOrNull { it.storageValue == value }
    }
}
