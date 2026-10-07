package com.bukovinafilip.gradey.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SupportPlanEligibilityTest {
    @Test
    fun rejectsTheCurrentPlanAndTierDowngrades() {
        assertThat(
            SupportPlanEligibility.canPurchase(
                entitlement = entitlement(GradeySupportTier.STANDARD, SupportBillingInterval.YEARLY),
                plan = plan(GradeySupportTier.STANDARD, SupportBillingInterval.YEARLY),
            ),
        ).isFalse()
        assertThat(
            SupportPlanEligibility.canPurchase(
                entitlement = entitlement(GradeySupportTier.PLUS, SupportBillingInterval.YEARLY),
                plan = plan(GradeySupportTier.STANDARD, SupportBillingInterval.MONTHLY),
            ),
        ).isFalse()
    }

    @Test
    fun allowsAnIntervalChangeAndTierUpgrade() {
        assertThat(
            SupportPlanEligibility.canPurchase(
                entitlement = entitlement(GradeySupportTier.STANDARD, SupportBillingInterval.YEARLY),
                plan = plan(GradeySupportTier.STANDARD, SupportBillingInterval.MONTHLY),
            ),
        ).isTrue()
        assertThat(
            SupportPlanEligibility.canPurchase(
                entitlement = entitlement(GradeySupportTier.STANDARD, SupportBillingInterval.MONTHLY),
                plan = plan(GradeySupportTier.PLUS, SupportBillingInterval.YEARLY),
            ),
        ).isTrue()
    }

    @Test
    fun allowsAPlanWhenThereIsNoActiveEntitlement() {
        assertThat(
            SupportPlanEligibility.canPurchase(
                entitlement = SupportEntitlement(),
                plan = plan(GradeySupportTier.STANDARD, SupportBillingInterval.MONTHLY),
            ),
        ).isTrue()
    }

    private fun entitlement(
        tier: GradeySupportTier,
        interval: SupportBillingInterval,
    ) = SupportEntitlement(tier = tier, interval = interval)

    private fun plan(
        tier: GradeySupportTier,
        interval: SupportBillingInterval,
    ) = SupportPlanOption(
        id = "$tier-$interval",
        productIdentifier = "product-$tier-$interval",
        tier = tier,
        interval = interval,
        localizedPrice = "$1.99",
    )
}
