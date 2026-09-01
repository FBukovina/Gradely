package com.bukovinafilip.gradey.feature.account

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.SupportBillingInterval
import com.bukovinafilip.gradey.model.SupportCatalog
import com.bukovinafilip.gradey.model.SupportEntitlement
import com.bukovinafilip.gradey.model.SupportPlanOption
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SupportBillingIntervalInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun yearlyEntitlementInitiallyShowsAndDisablesTheExactCurrentPlan() {
        val purchasedPlan = AtomicReference<SupportPlanOption?>()
        setOptions(onPurchasePlan = purchasedPlan::set)

        composeRule.onNodeWithText(yearlyLabel).assertIsSelected()
        composeRule.onNodeWithText(monthlyLabel).assertIsNotSelected()
        composeRule.onNodeWithText(yearlyPriceLabel)
            .assertIsDisplayed()
            .assertIsNotEnabled()
        composeRule.onNodeWithText(currentLabel).assertIsDisplayed()
        composeRule.onNodeWithText(monthlyPriceLabel).assertDoesNotExist()
        composeRule.runOnIdle { assertNull(purchasedPlan.get()) }
    }

    @Test
    fun explicitMonthlySelectionSurvivesRestorationAndPurchasesExactMonthlyPlan() {
        val restorationTester = StateRestorationTester(composeRule)
        val purchasedPlan = AtomicReference<SupportPlanOption?>()
        restorationTester.setContent {
            TestOptions(onPurchasePlan = purchasedPlan::set)
        }

        composeRule.onNodeWithText(monthlyLabel).performClick().assertIsSelected()
        composeRule.onNodeWithText(yearlyLabel).assertIsNotSelected()
        composeRule.onNodeWithText(monthlyPriceLabel).assertIsDisplayed().assertIsEnabled()

        restorationTester.emulateSavedInstanceStateRestore()

        composeRule.onNodeWithText(monthlyLabel).assertIsSelected()
        composeRule.onNodeWithText(yearlyLabel).assertIsNotSelected()
        composeRule.onNodeWithText(monthlyPriceLabel).assertIsEnabled().performClick()
        composeRule.runOnIdle { assertEquals(MonthlyPlan, purchasedPlan.get()) }
    }

    @Test
    fun sameEntitlementCatalogRefreshKeepsExplicitIntervalSelection() {
        val purchasedPlan = AtomicReference<SupportPlanOption?>()
        composeRule.setContent {
            var recompositionTick by remember { mutableIntStateOf(0) }
            TestOptions(
                onPurchasePlan = purchasedPlan::set,
                onReload = { recompositionTick += 1 },
                catalog = YearlyCatalog.copy(
                    entitlement = YearlyCatalog.entitlement.copy(
                        expirationEpochMillis = recompositionTick.toLong(),
                        willRenew = recompositionTick % 2 == 1,
                    ),
                ),
            )
        }

        composeRule.onNodeWithText(monthlyLabel).performClick().assertIsSelected()
        composeRule.onNodeWithText(context.getString(R.string.support_restore)).performClick()
        composeRule.onNodeWithText(monthlyLabel).assertIsSelected()
        composeRule.runOnIdle { assertNull(purchasedPlan.get()) }
    }

    @Test
    fun changedEntitlementReseedsIntervalAcrossStateRestoration() {
        val restorationTester = StateRestorationTester(composeRule)
        val currentCatalog = AtomicReference(YearlyCatalog)
        restorationTester.setContent {
            TestOptions(
                catalog = currentCatalog.get(),
                onPurchasePlan = {},
            )
        }

        composeRule.onNodeWithText(monthlyLabel).performClick().assertIsSelected()
        currentCatalog.set(
            YearlyCatalog.copy(
                entitlement = YearlyCatalog.entitlement.copy(
                    tier = GradeySupportTier.PLUS,
                    productIdentifier = "gradey_plus_yearly",
                ),
            ),
        )

        restorationTester.emulateSavedInstanceStateRestore()

        composeRule.onNodeWithText(yearlyLabel).assertIsSelected()
        composeRule.onNodeWithText(monthlyLabel).assertIsNotSelected()
    }

    private fun setOptions(onPurchasePlan: (SupportPlanOption) -> Unit) {
        composeRule.setContent { TestOptions(onPurchasePlan = onPurchasePlan) }
    }

    @Composable
    private fun TestOptions(
        onPurchasePlan: (SupportPlanOption) -> Unit,
        onReload: () -> Unit = {},
        catalog: SupportCatalog = YearlyCatalog,
    ) {
        GradeyTheme {
            OnboardingSupportOptionsContent(
                catalog = catalog,
                isSignedIn = true,
                isConfigured = true,
                isLoading = false,
                purchasingOptionID = null,
                isRestoring = false,
                message = null,
                onReload = onReload,
                onPurchasePlan = onPurchasePlan,
                onPurchaseTip = {},
                onRestore = onReload,
                onManageSubscription = {},
                onOpenPrivacyPolicy = {},
                onOpenTermsOfUse = {},
            )
        }
    }

    private val monthlyLabel get() = context.getString(R.string.support_monthly)
    private val yearlyLabel get() = context.getString(R.string.support_yearly)
    private val currentLabel get() = context.getString(R.string.support_current)
    private val monthlyPriceLabel
        get() = context.getString(
            R.string.support_ai_per_day,
            MonthlyPlan.localizedPrice,
            MonthlyPlan.tier.dailyAILimit,
        )
    private val yearlyPriceLabel
        get() = context.getString(
            R.string.support_ai_per_day,
            YearlyPlan.localizedPrice,
            YearlyPlan.tier.dailyAILimit,
        )

    private companion object {
        val MonthlyPlan = SupportPlanOption(
            id = "standard-monthly-offer",
            productIdentifier = "gradey_standard_monthly",
            tier = GradeySupportTier.STANDARD,
            interval = SupportBillingInterval.MONTHLY,
            localizedPrice = "$1.99",
        )
        val YearlyPlan = SupportPlanOption(
            id = "standard-yearly-offer",
            productIdentifier = "gradey_standard_yearly",
            tier = GradeySupportTier.STANDARD,
            interval = SupportBillingInterval.YEARLY,
            localizedPrice = "$19.99",
        )
        val YearlyCatalog = SupportCatalog(
            plans = listOf(MonthlyPlan, YearlyPlan),
            entitlement = SupportEntitlement(
                tier = GradeySupportTier.STANDARD,
                interval = SupportBillingInterval.YEARLY,
                productIdentifier = YearlyPlan.productIdentifier,
            ),
        )
    }
}
