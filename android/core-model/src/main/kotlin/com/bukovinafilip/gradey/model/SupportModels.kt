package com.bukovinafilip.gradey.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class GradeySupportTier {
    @SerialName("none")
    NONE,

    @SerialName("standard")
    STANDARD,

    @SerialName("plus")
    PLUS;

    val dailyAILimit: Int
        get() = when (this) {
            NONE -> 5
            STANDARD -> 10
            PLUS -> 25
        }
}

@Serializable
enum class SupportBillingInterval {
    @SerialName("monthly")
    MONTHLY,

    @SerialName("yearly")
    YEARLY,
}

data class SupportPlanOption(
    val id: String,
    val productIdentifier: String,
    val tier: GradeySupportTier,
    val interval: SupportBillingInterval,
    val localizedPrice: String,
)

data class SupportTipOption(
    val id: String,
    val productIdentifier: String,
    val title: String,
    val localizedPrice: String,
)

data class SupportEntitlement(
    val tier: GradeySupportTier = GradeySupportTier.NONE,
    val interval: SupportBillingInterval? = null,
    val productIdentifier: String? = null,
    val expirationEpochMillis: Long? = null,
    val willRenew: Boolean = false,
    val managementURL: String? = null,
)

data class SupportCatalog(
    val tips: List<SupportTipOption> = emptyList(),
    val plans: List<SupportPlanOption> = emptyList(),
    val entitlement: SupportEntitlement = SupportEntitlement(),
    val managementURL: String? = null,
) {
    val isEmpty: Boolean get() = tips.isEmpty() && plans.isEmpty()
}

enum class SupportPurchaseOutcome {
    SUCCESS,
    PENDING,
    CANCELLED,
}
