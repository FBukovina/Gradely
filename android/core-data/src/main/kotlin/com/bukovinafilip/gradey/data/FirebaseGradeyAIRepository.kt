package com.bukovinafilip.gradey.data

import android.content.Context
import com.bukovinafilip.gradey.domain.GradeyAIErrorClassifier
import com.bukovinafilip.gradey.domain.GradeyAIErrorKind
import com.bukovinafilip.gradey.domain.GradeyAIException
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.model.GradeyAIConsent
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAIConversation
import com.bukovinafilip.gradey.model.GradeyAIConversationDetail
import com.bukovinafilip.gradey.model.GradeyAIIdentityTier
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.bukovinafilip.gradey.model.GradeyAIStreamEvent
import com.google.firebase.FirebaseException
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.functions.FirebaseFunctionsException
import com.google.firebase.functions.HttpsCallableOptions
import com.google.firebase.functions.StreamResponse
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.reactive.asFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await

class FirebaseGradeyAIRepository(
    context: Context,
    private val gradeyAuthRepository: GradeyAuthRepository,
) : GradeyAIRepository {
    private val applicationContext = context.applicationContext
    private val identityCoordinator = FirebaseGradeyAIIdentityCoordinator()

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
        val response = call(
            name = "gradeyAIRevokeConsent",
            payload = accountPayload(),
        )
        FirebaseGradeyAIWire.requireSuccessfulMutation(response, "consent revocation")
        if ((response as? Map<*, *>)?.boolean("anonymousIdentityDeleted", "anonymous_identity_deleted") == true) {
            FirebaseAuth.getInstance(firebaseApp()).signOut()
        }
    }

    override suspend fun listConversations(schoolScope: String): List<GradeyAIConversation> =
        FirebaseGradeyAIWire.decodeConversations(
            call(
                name = "gradeyAIListChats",
                payload = schoolScopePayload(schoolScope),
            ),
        )

    override suspend fun createConversation(
        schoolScope: String,
        title: String?,
    ): GradeyAIConversation = FirebaseGradeyAIWire.decodeConversationEnvelope(
        call(
            name = "gradeyAICreateChat",
            payload = buildMap {
                put("schoolScope", schoolScope)
                put("title", title)
                gradeyAccountID()?.let { put("gradey_account_id", it) }
            },
        ),
    )

    override suspend fun loadConversation(id: String): GradeyAIConversationDetail =
        FirebaseGradeyAIWire.decodeConversationDetail(
            payload = call(name = "gradeyAILoadChat", payload = conversationPayload(id)),
            fallbackConversationID = id,
        )

    override suspend fun deleteConversation(id: String) {
        FirebaseGradeyAIWire.requireSuccessfulMutation(
            payload = call(name = "gradeyAIDeleteChat", payload = conversationPayload(id)),
            operation = "conversation deletion",
        )
    }

    override suspend fun deleteAllConversations(schoolScope: String) {
        FirebaseGradeyAIWire.requireSuccessfulMutation(
            payload = call(name = "gradeyAIDeleteAll", payload = schoolScopePayload(schoolScope)),
            operation = "conversation deletion",
        )
    }

    override fun streamReply(
        conversationID: String,
        clientMessageID: String,
        text: String,
        context: GradeyAIContextSnapshot,
        locale: String,
    ): Flow<GradeyAIStreamEvent> = flow {
        try {
            val app = firebaseApp()
            val accountID = gradeyAccountID()
            val payload = FirebaseGradeyAIRequestBuilder.streamPayload(
                conversationID = conversationID,
                clientMessageID = clientMessageID,
                text = text,
                locale = locale,
                context = context,
                gradeyAccountID = accountID,
            )
            ensureIdentity(app)
            val options = HttpsCallableOptions.Builder()
                .setLimitedUseAppCheckTokens(true)
                .build()
            val callable = FirebaseFunctions.getInstance(app, Region)
                .getHttpsCallable("gradeyAIStreamReply", options)
                .withTimeout(CallableTimeoutSeconds, TimeUnit.SECONDS)
            var receivedTerminalEvent = false
            callable.stream(payload).asFlow().collect { response ->
                if (response is StreamResponse.Result && receivedTerminalEvent) return@collect
                val data = when (response) {
                    is StreamResponse.Message -> response.message.data
                    is StreamResponse.Result -> response.result.data
                    else -> throw GradeyAIException(
                        GradeyAIErrorKind.MALFORMED_RESPONSE,
                        "Gradey AI returned an unsupported stream response.",
                    )
                }
                val event = FirebaseGradeyAIWire.decodeStreamEvent(data, conversationID)
                emit(event)
                if (event is GradeyAIStreamEvent.Done || event is GradeyAIStreamEvent.Error) {
                    receivedTerminalEvent = true
                }
            }
            if (!receivedTerminalEvent) {
                throw GradeyAIException(
                    GradeyAIErrorKind.MALFORMED_RESPONSE,
                    "Gradey AI ended the reply before returning a result.",
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            throw FirebaseGradeyAIErrorMapper.map(error)
        }
    }

    private suspend fun call(name: String, payload: Map<String, Any?>): Any? = try {
        val app = firebaseApp()
        ensureIdentity(app)
        val options = HttpsCallableOptions.Builder()
            .setLimitedUseAppCheckTokens(true)
            .build()
        FirebaseFunctions.getInstance(app, Region)
            .getHttpsCallable(name, options)
            .withTimeout(CallableTimeoutSeconds, TimeUnit.SECONDS)
            .call(payload)
            .await()
            .data
    } catch (error: CancellationException) {
        throw error
    } catch (error: Throwable) {
        throw FirebaseGradeyAIErrorMapper.map(error)
    }

    private suspend fun ensureIdentity(app: FirebaseApp) {
        identityCoordinator.serialized {
            val auth = FirebaseAuth.getInstance(app)
            val currentUser = auth.currentUser
            if (currentUser != null) {
                try {
                    currentUser.getIdToken(false).await()
                    return@serialized
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    auth.signOut()
                }
            }
            auth.signInAnonymously().await()
        }
    }

    private suspend fun accountPayload(): Map<String, Any?> = buildMap {
        gradeyAccountID()?.let { put("gradey_account_id", it) }
    }

    private suspend fun schoolScopePayload(schoolScope: String): Map<String, Any?> = buildMap {
        put("schoolScope", schoolScope)
        gradeyAccountID()?.let { put("gradey_account_id", it) }
    }

    private suspend fun conversationPayload(id: String): Map<String, Any?> = buildMap {
        put("chatID", id)
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
        ?: throw GradeyAIException(
            GradeyAIErrorKind.NOT_CONFIGURED,
            "Gradey AI is not configured in this build.",
        )

    private companion object {
        const val Region = "europe-west1"
        const val CallableTimeoutSeconds = 120L
    }
}

internal class FirebaseGradeyAIIdentityCoordinator {
    private val mutex = Mutex()

    suspend fun <T> serialized(block: suspend () -> T): T = mutex.withLock { block() }
}

internal object FirebaseGradeyAIErrorMapper {
    fun map(error: Throwable): Throwable {
        if (error is CancellationException || error is GradeyAIException) return error
        if (error is FirebaseAuthException) {
            return GradeyAIException(
                GradeyAIErrorKind.UNAUTHENTICATED,
                "Gradey AI couldn’t start a secure session. Try again.",
                retryable = true,
                cause = error,
            )
        }
        if (error is FirebaseFunctionsException) {
            val details = error.details as? Map<*, *>
            val detailCode = details?.string("code")
            val code = detailCode ?: error.code.name.lowercase()
            val message = details?.string("message") ?: error.message ?: "Gradey AI request failed."
            if (error.code == FirebaseFunctionsException.Code.UNAUTHENTICATED) {
                return GradeyAIException(
                    GradeyAIErrorKind.UNAUTHENTICATED,
                    "Gradey AI couldn’t start a secure session. Try again.",
                    retryable = true,
                    serverCode = code,
                    cause = error,
                )
            }
            val retryable = details?.boolean("retryable") ?: (error.code in RetryableCodes)
            return GradeyAIErrorClassifier.server(code, message, retryable, error)
        }
        if (error is IOException || error is FirebaseException) {
            return GradeyAIException(
                GradeyAIErrorKind.TRANSPORT,
                error.message ?: "Check your connection and try again.",
                retryable = true,
                cause = error,
            )
        }
        return GradeyAIException(
            GradeyAIErrorKind.TRANSPORT,
            error.message ?: "Gradey AI request failed.",
            retryable = true,
            cause = error,
        )
    }

    private val RetryableCodes = setOf(
        FirebaseFunctionsException.Code.CANCELLED,
        FirebaseFunctionsException.Code.DEADLINE_EXCEEDED,
        FirebaseFunctionsException.Code.RESOURCE_EXHAUSTED,
        FirebaseFunctionsException.Code.ABORTED,
        FirebaseFunctionsException.Code.INTERNAL,
        FirebaseFunctionsException.Code.UNAVAILABLE,
    )
}

internal object FirebaseGradeyAIStatusMapper {
    fun decode(payload: Any?): GradeyAIStatus {
        val values = payload as? Map<*, *>
            ?: throw GradeyAIException(
                GradeyAIErrorKind.MALFORMED_RESPONSE,
                "Gradey AI returned an invalid status response.",
            )
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
            resetAtEpochMillis = values.epochMillis("resetAt", "reset_at"),
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
