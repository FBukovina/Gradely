package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.SupportBillingInterval

data class SupportPlanKind(
    val tier: GradeySupportTier,
    val interval: SupportBillingInterval,
)

object SupportCatalogRules {
    const val SUPPORT_OFFERING_ID = "support"
    const val TIPS_OFFERING_ID = "tips"
    const val STANDARD_ENTITLEMENT_ID = "support"
    const val PLUS_ENTITLEMENT_ID = "support_plus"

    fun planKind(vararg identifiers: String?): SupportPlanKind? {
        val value = identifiers.filterNotNull().joinToString(" ").lowercase()
        val tier = when {
            containsToken(value, "plus") -> GradeySupportTier.PLUS
            containsToken(value, "standard") -> GradeySupportTier.STANDARD
            else -> return null
        }
        val interval = when {
            value.contains("year") || value.contains("annual") -> SupportBillingInterval.YEARLY
            value.contains("month") -> SupportBillingInterval.MONTHLY
            else -> return null
        }
        return SupportPlanKind(tier, interval)
    }

    fun entitlementTier(activeEntitlementIDs: Set<String>): GradeySupportTier = when {
        PLUS_ENTITLEMENT_ID in activeEntitlementIDs -> GradeySupportTier.PLUS
        STANDARD_ENTITLEMENT_ID in activeEntitlementIDs -> GradeySupportTier.STANDARD
        else -> GradeySupportTier.NONE
    }

    private fun containsToken(value: String, token: String): Boolean =
        value.split('.', ':', '-', '_', ' ', '/').any { it == token }
}
