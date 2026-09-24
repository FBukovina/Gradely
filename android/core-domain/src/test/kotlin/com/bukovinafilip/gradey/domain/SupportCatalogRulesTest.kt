package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.SupportBillingInterval
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SupportCatalogRulesTest {
    @Test
    fun mapsCustomPackageAndGoogleBasePlanIdentifiers() {
        assertThat(SupportCatalogRules.planKind("support_standard_monthly", null, null))
            .isEqualTo(SupportPlanKind(GradeySupportTier.STANDARD, SupportBillingInterval.MONTHLY))
        assertThat(
            SupportCatalogRules.planKind(
                "\$rc_annual",
                "com.bukovinafilip.gradey.support",
                "support_plus_yearly",
            ),
        ).isEqualTo(SupportPlanKind(GradeySupportTier.PLUS, SupportBillingInterval.YEARLY))
        assertThat(SupportCatalogRules.planKind("tip_small", "gradey.tip.small", null)).isNull()
    }

    @Test
    fun plusEntitlementWinsAndUnknownEntitlementsStayFree() {
        assertThat(SupportCatalogRules.entitlementTier(setOf("support", "support_plus")))
            .isEqualTo(GradeySupportTier.PLUS)
        assertThat(SupportCatalogRules.entitlementTier(setOf("support")))
            .isEqualTo(GradeySupportTier.STANDARD)
        assertThat(SupportCatalogRules.entitlementTier(setOf("unrelated")))
            .isEqualTo(GradeySupportTier.NONE)
    }
}
