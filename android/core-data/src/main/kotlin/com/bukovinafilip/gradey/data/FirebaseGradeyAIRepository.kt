package com.bukovinafilip.gradey.data

import android.content.Context
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.model.GradeyAIConsent
import com.bukovinafilip.gradey.model.GradeyAIIdentityTier
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.functions.HttpsCallableOptions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await
import kotlin.math.roundToLong

class FirebaseGradeyAIRepository(
    context: Context,
    private val gradeyAuthRepository: GradeyAuthRepository,
) : GradeyAIRepository {
    private val applicationContext = context.applicationContext

    override val isConfigured: Boolean
        get() = FirebaseApp.getApps(applicationContext).isNotEmpty()

    override suspend fun loadStatus(): GradeyAIStatus = FirebaseGradeyAIStatusMapper.decode(
        call(
            name = "gradeyAIGetStatus",
            payload = accountPayload(),
        ),
    )

    override suspend fun acceptConsent(): GradeyAIConsent {
        val current = loadStatus()
        val response = call(
            name = "gradeyAIAcceptConsent",
            payload = buildMap {
                put("termsVersion", current.termsVersion)
                gradeyAccountID()?.let { put("gradey_account_id", it) }
            },
        )
        val status = (response as? Map<*, *>)?.get("status")
            ?.let(FirebaseGradeyAIStatusMapper::decode)
        return GradeyAIConsent(
            consented = true,
            termsVersion = status?.termsVersion ?: current.termsVersion,
        )
    }

    override suspend fun revokeConsent() {
        call(
            name = "gradeyAIRevokeConsent",
            payload = accountPayload(),
        )
    }

    private suspend fun call(name: String, payload: Map<String, Any?>): Any? {
        val app = firebaseApp()
        ensureIdentity(app)
        val options = HttpsCallableOptions.Builder()
            .setLimitedUseAppCheckTokens(true)
            .build()
        return FirebaseFunctions.getInstance(app, Region)
            .getHttpsCallable(name, options)
            .call(payload)
            .await()
            .getData()
    }

    private suspend fun ensureIdentity(app: FirebaseApp) {
        val auth = FirebaseAuth.getInstance(app)
        val currentUser = auth.currentUser
        if (currentUser != null) {
            try {
                currentUser.getIdToken(false).await()
                return
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                auth.signOut()
            }
        }
        auth.signInAnonymously().await()
    }

    private suspend fun accountPayload(): Map<String, Any?> = buildMap {
        gradeyAccountID()?.let { put("gradey_account_id", it) }
    }

    private suspend fun gradeyAccountID(): String? = try {
        gradeyAuthRepository
            .bootstrapSession()
            ?.account
            ?.id
            ?.trim()
            ?.takeIf(String::isNotEmpty)
    } catch (error: CancellationException) {
        throw error
    } catch (_: Throwable) {
        null
    }

    private fun firebaseApp(): FirebaseApp = FirebaseApp.getApps(applicationContext).firstOrNull()
        ?: throw FeatureUnavailableException("Gradey AI is not configured in this build.")

    private companion object {
        const val Region = "europe-west1"
    }
}

internal object FirebaseGradeyAIStatusMapper {
    fun decode(payload: Any?): GradeyAIStatus {
        val values = payload as? Map<*, *>
            ?: throw IllegalStateException("Gradey AI returned an invalid status response.")
        val enabled = values.boolean("enabled") ?: false
        val consentRequired = values.boolean("consentRequired", "consent_required") ?: true
        val termsVersion = values.string("termsVersion", "terms_version").orEmpty()
        val dailyLimit = values.integer("dailyLimit", "daily_limit") ?: 5
        val dailyUsed = values.integer("dailyUsed", "daily_used") ?: 0
        val remaining = values.integer("remaining") ?: (dailyLimit - dailyUsed).coerceAtLeast(0)
        val tier = when (values.string("tier")) {
            "linked" -> GradeyAIIdentityTier.LINKED
            else -> GradeyAIIdentityTier.ANONYMOUS
        }
        return GradeyAIStatus(
            enabled = enabled,
            consentRequired = consentRequired,
            termsVersion = termsVersion,
            dailyLimit = dailyLimit,
            dailyUsed = dailyUsed,
            remaining = remaining,
            resetAtEpochMillis = values.number("resetAt", "reset_at")?.roundToLong(),
            tier = tier,
        )
    }

    private fun Map<*, *>.value(vararg names: String): Any? = names.firstNotNullOfOrNull { this[it] }

    private fun Map<*, *>.string(vararg names: String): String? = when (val value = value(*names)) {
        is String -> value
        is Number, is Boolean -> value.toString()
        else -> null
    }

    private fun Map<*, *>.boolean(vararg names: String): Boolean? = when (val value = value(*names)) {
        is Boolean -> value
        is Number -> value.toInt() != 0
        is String -> value.toBooleanStrictOrNull() ?: value.toIntOrNull()?.let { it != 0 }
        else -> null
    }

    private fun Map<*, *>.integer(vararg names: String): Int? = when (val value = value(*names)) {
        is Number -> value.toInt()
        is String -> value.toDoubleOrNull()?.toInt()
        else -> null
    }

    private fun Map<*, *>.number(vararg names: String): Double? = when (val value = value(*names)) {
        is Number -> value.toDouble()
        is String -> value.toDoubleOrNull()
        else -> null
    }
}
