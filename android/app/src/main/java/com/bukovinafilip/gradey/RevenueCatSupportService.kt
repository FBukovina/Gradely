package com.bukovinafilip.gradey

import android.app.Activity
import com.bukovinafilip.gradey.domain.SupportCatalogRules
import com.bukovinafilip.gradey.model.GradeySupportTier
import com.bukovinafilip.gradey.model.SupportCatalog
import com.bukovinafilip.gradey.model.SupportEntitlement
import com.bukovinafilip.gradey.model.SupportPlanOption
import com.bukovinafilip.gradey.model.SupportPurchaseOutcome
import com.bukovinafilip.gradey.model.SupportTipOption
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitLogIn
import com.revenuecat.purchases.awaitLogOut
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class RevenueCatPurchaseResult(
    val outcome: SupportPurchaseOutcome,
    val entitlement: SupportEntitlement,
)

class RevenueCatSupportService {
    private val mutex = Mutex()
    private var packagesByID: Map<String, Package> = emptyMap()
    private var lastEntitlement = SupportEntitlement()
    private var lastOriginalAppUserID: String? = null

    val isConfigured: Boolean get() = Purchases.isConfigured
    val diagnosticAppUserID: String?
        get() = if (isConfigured) runCatching { Purchases.sharedInstance.appUserID }.getOrNull() else null
    val diagnosticOriginalAppUserID: String? get() = lastOriginalAppUserID

    suspend fun syncIdentity(accountID: String?): SupportEntitlement = mutex.withLock {
        val purchases = configuredPurchases()
        when {
            accountID != null && purchases.appUserID != accountID -> purchases.awaitLogIn(accountID)
            accountID == null && !purchases.isAnonymous -> purchases.awaitLogOut()
        }
        entitlement(purchases.awaitCustomerInfo()).also { lastEntitlement = it }
    }

    suspend fun loadCatalog(accountID: String?): SupportCatalog = mutex.withLock {
        val purchases = configuredPurchases()
        when {
            accountID != null && purchases.appUserID != accountID -> purchases.awaitLogIn(accountID)
            accountID == null && !purchases.isAnonymous -> purchases.awaitLogOut()
        }

        val offerings = purchases.awaitOfferings()
        val supportPackages = offerings[SupportCatalogRules.SUPPORT_OFFERING_ID]
            ?.availablePackages
            .orEmpty()
        val tipPackages = offerings[SupportCatalogRules.TIPS_OFFERING_ID]
            ?.availablePackages
            .orEmpty()
        packagesByID = (supportPackages + tipPackages).associateBy(Package::identifier)

        val plans = supportPackages.mapNotNull { storePackage ->
            val kind = SupportCatalogRules.planKind(
                storePackage.identifier,
                storePackage.product.id,
                storePackage.product.defaultOption?.id,
            ) ?: return@mapNotNull null
            SupportPlanOption(
                id = storePackage.identifier,
                productIdentifier = storePackage.product.id,
                tier = kind.tier,
                interval = kind.interval,
                localizedPrice = storePackage.product.price.formatted,
            )
        }.sortedWith(compareBy({ it.interval.ordinal }, { it.tier.ordinal }))
        val tips = tipPackages.map { storePackage ->
            SupportTipOption(
                id = storePackage.identifier,
                productIdentifier = storePackage.product.id,
                title = storePackage.product.name.trim().ifEmpty { storePackage.identifier },
                localizedPrice = storePackage.product.price.formatted,
            )
        }
        val customerInfo = purchases.awaitCustomerInfo()
        val current = entitlement(customerInfo).also { lastEntitlement = it }
        SupportCatalog(
            tips = tips,
            plans = plans,
            entitlement = current,
            managementURL = current.managementURL,
        )
    }

    suspend fun purchase(activity: Activity, optionID: String): RevenueCatPurchaseResult = mutex.withLock {
        val purchases = configuredPurchases()
        val storePackage = packagesByID[optionID]
            ?: throw SupportServiceException(SupportServiceError.OPTION_UNAVAILABLE)
        try {
            val result = purchases.awaitPurchase(
                PurchaseParams.Builder(activity, storePackage).build(),
            )
            RevenueCatPurchaseResult(
                outcome = SupportPurchaseOutcome.SUCCESS,
                entitlement = entitlement(result.customerInfo).also { lastEntitlement = it },
            )
        } catch (error: PurchasesTransactionException) {
            val outcome = when {
                error.userCancelled || error.code == PurchasesErrorCode.PurchaseCancelledError -> {
                    SupportPurchaseOutcome.CANCELLED
                }
                error.code == PurchasesErrorCode.PaymentPendingError -> SupportPurchaseOutcome.PENDING
                else -> throw error
            }
            RevenueCatPurchaseResult(
                outcome = outcome,
                entitlement = lastEntitlement,
            )
        }
    }

    suspend fun restore(accountID: String?): SupportEntitlement = mutex.withLock {
        val purchases = configuredPurchases()
        if (accountID == null) throw SupportServiceException(SupportServiceError.SIGN_IN_REQUIRED)
        if (purchases.appUserID != accountID) purchases.awaitLogIn(accountID)
        entitlement(purchases.awaitRestore()).also { lastEntitlement = it }
    }

    private fun configuredPurchases(): Purchases {
        if (!Purchases.isConfigured) {
            throw SupportServiceException(SupportServiceError.NOT_CONFIGURED)
        }
        return Purchases.sharedInstance
    }

    private fun entitlement(customerInfo: CustomerInfo): SupportEntitlement {
        lastOriginalAppUserID = customerInfo.originalAppUserId
        val active = customerInfo.entitlements.active
        val tier = SupportCatalogRules.entitlementTier(active.keys)
        val info = when (tier) {
            GradeySupportTier.PLUS -> active[SupportCatalogRules.PLUS_ENTITLEMENT_ID]
            GradeySupportTier.STANDARD -> active[SupportCatalogRules.STANDARD_ENTITLEMENT_ID]
            GradeySupportTier.NONE -> null
        }
        val kind = info?.let {
            SupportCatalogRules.planKind(it.productIdentifier, it.productPlanIdentifier)
        }
        return SupportEntitlement(
            tier = tier,
            interval = kind?.interval,
            productIdentifier = info?.productIdentifier,
            expirationEpochMillis = info?.expirationDate?.time,
            willRenew = info?.willRenew == true,
            managementURL = customerInfo.managementURL?.toString(),
        )
    }
}
