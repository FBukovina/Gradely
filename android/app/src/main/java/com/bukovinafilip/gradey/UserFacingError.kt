package com.bukovinafilip.gradey

import android.content.Context
import androidx.annotation.StringRes
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import androidx.credentials.exceptions.GetCredentialUnsupportedException
import androidx.credentials.exceptions.NoCredentialException
import com.bukovinafilip.gradey.data.FeatureUnavailableException
import com.bukovinafilip.gradey.data.SchoolDirectoryException
import com.bukovinafilip.gradey.domain.GradeyAIContextError
import com.bukovinafilip.gradey.domain.GradeyAIContextException
import com.bukovinafilip.gradey.domain.GradeyAIErrorKind
import com.bukovinafilip.gradey.domain.GradeyAIException
import com.bukovinafilip.gradey.domain.GradeySessionExpiredException
import com.bukovinafilip.gradey.domain.InvalidDemoAccountCredentialsException
import com.bukovinafilip.gradey.domain.InvalidSchoolUrl
import com.bukovinafilip.gradey.domain.SchoolSessionExpiredException
import com.bukovinafilip.gradey.domain.StravaCZAppError
import com.bukovinafilip.gradey.domain.StravaCZAppException
import com.bukovinafilip.gradey.domain.StravaCZErrorKind
import com.bukovinafilip.gradey.domain.StravaCZException
import com.bukovinafilip.gradey.network.BakalariApiException
import com.bukovinafilip.gradey.network.BakalariErrorKind
import com.bukovinafilip.gradey.network.GradeyApiException
import com.bukovinafilip.gradey.network.GradeyFunctionException
import com.bukovinafilip.gradey.network.SchoolDirectoryNetworkException
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import java.io.InterruptedIOException
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.Collections
import java.util.IdentityHashMap
import kotlinx.serialization.SerializationException

/** A localizable, non-sensitive description that is safe to render directly. */
internal data class UserFacingError(
    @StringRes val messageRes: Int,
    val formatArguments: List<Any> = emptyList(),
) {
    fun resolve(context: Context): String =
        context.getString(messageRes, *formatArguments.toTypedArray())
}

internal enum class AppAuthError {
    GOOGLE_NOT_CONFIGURED,
    GOOGLE_UNSUPPORTED_CREDENTIAL,
}

internal class AppAuthException(
    val error: AppAuthError,
) : IllegalStateException()

internal enum class SupportServiceError {
    OPTION_UNAVAILABLE,
    SIGN_IN_REQUIRED,
    NOT_CONFIGURED,
}

internal class SupportServiceException(
    val error: SupportServiceError,
) : IllegalStateException()

/**
 * Converts an arbitrary failure into a resource key without ever copying Throwable.message.
 *
 * Several network layers intentionally retain response bodies for diagnostics. Those bodies can
 * contain HTML, credentials, tokens, or backend implementation details, so they never cross this
 * boundary. The only dynamic value rendered here is a numeric HTTP status code.
 */
internal fun Throwable.toUserFacingError(): UserFacingError {
    val causes = causalChain()
    return causes.firstNotNullOfOrNull(::mapDomainOrServiceError)
        ?: causes.firstNotNullOfOrNull(::mapPlatformError)
        ?: mapFallbackError(this)
}

internal fun Throwable.userFacingMessage(context: Context): String =
    toUserFacingError().resolve(context)

private fun mapDomainOrServiceError(error: Throwable): UserFacingError? = when (error) {
    is SchoolSessionExpiredException -> resource(R.string.school_session_expired)
    is GradeySessionExpiredException -> resource(R.string.error_gradey_session_expired)
    is BakalariApiException -> error.toUserFacingError()
    is GradeyFunctionException -> error.toUserFacingError()
    is GradeyApiException -> error.toUserFacingError()
    is SchoolDirectoryException,
    is SchoolDirectoryNetworkException,
    -> resource(R.string.school_directory_load_failed)
    is FeatureUnavailableException -> resource(R.string.error_feature_unavailable)
    is InvalidSchoolUrl -> resource(R.string.error_invalid_school_url)
    is InvalidDemoAccountCredentialsException -> resource(R.string.error_invalid_demo_credentials)
    is GradeyAIException -> error.toUserFacingError()
    is GradeyAIContextException -> error.toUserFacingError()
    is StravaCZException -> error.toUserFacingError()
    is StravaCZAppException -> error.toUserFacingError()
    is AppAuthException -> when (error.error) {
        AppAuthError.GOOGLE_NOT_CONFIGURED -> resource(R.string.google_sign_in_not_configured)
        AppAuthError.GOOGLE_UNSUPPORTED_CREDENTIAL -> resource(R.string.google_sign_in_unsupported)
    }
    is SupportServiceException -> when (error.error) {
        SupportServiceError.OPTION_UNAVAILABLE -> resource(R.string.error_purchase_option_unavailable)
        SupportServiceError.SIGN_IN_REQUIRED -> resource(R.string.error_purchase_sign_in_required)
        SupportServiceError.NOT_CONFIGURED -> resource(R.string.error_purchase_not_configured)
    }
    is PurchasesException -> purchaseError(error.code)
    else -> null
}

private fun mapPlatformError(error: Throwable): UserFacingError? = when (error) {
    is GetCredentialCancellationException -> resource(R.string.error_google_sign_in_cancelled)
    is NoCredentialException -> resource(R.string.error_google_sign_in_no_account)
    is GetCredentialProviderConfigurationException,
    is GetCredentialUnsupportedException,
    -> resource(R.string.error_google_sign_in_unavailable)
    is GetCredentialException -> resource(R.string.error_google_sign_in_failed)
    is SocketTimeoutException,
    is InterruptedIOException,
    -> resource(R.string.error_request_timeout)
    is UnknownHostException,
    is ConnectException,
    is NoRouteToHostException,
    -> resource(R.string.error_offline)
    is SerializationException -> resource(R.string.error_unreadable_response)
    is IOException -> resource(R.string.error_connection_failed)
    is SecurityException -> resource(R.string.error_permission_denied)
    else -> null
}

private fun mapFallbackError(error: Throwable): UserFacingError = when (error) {
    is IllegalArgumentException -> resource(R.string.error_invalid_request)
    else -> resource(R.string.generic_error)
}

private fun BakalariApiException.toUserFacingError(): UserFacingError = when (kind) {
    BakalariErrorKind.AUTHENTICATION -> resource(R.string.error_school_authentication)
    BakalariErrorKind.TIMEOUT -> resource(R.string.error_request_timeout)
    BakalariErrorKind.OFFLINE -> resource(R.string.error_offline)
    BakalariErrorKind.TRANSPORT -> resource(R.string.error_connection_failed)
    BakalariErrorKind.DECODING -> resource(R.string.error_school_decoding)
    BakalariErrorKind.INVALID_RESPONSE -> resource(R.string.error_school_invalid_response)
    BakalariErrorKind.HTTP -> statusCode
        ?.let { resource(R.string.error_school_http, it) }
        ?: resource(R.string.error_school_server)
}

private fun GradeyFunctionException.toUserFacingError(): UserFacingError {
    if (statusCode == 401 || statusCode == 403) {
        return resource(R.string.error_gradey_authentication)
    }
    if (statusCode == 408) return resource(R.string.error_request_timeout)
    if (statusCode == 429) return resource(R.string.error_rate_limited)

    return when (function) {
        "grade-history" -> resource(R.string.error_grade_history)
        "account-settings",
        "link-school-account",
        "link-stravacz-account",
        "activate-school-account",
        "relink-school-account",
        "update-linked-account-preferences",
        "unlink-account",
        -> resource(R.string.error_linked_account)
        "register-device", "update-notification-preferences" ->
            resource(R.string.error_notification_preferences)
        "request-data-export" -> resource(R.string.error_data_export)
        "delete-account" -> resource(R.string.error_account_deletion)
        else -> resource(R.string.error_gradey_http, statusCode)
    }
}

private fun GradeyApiException.toUserFacingError(): UserFacingError = when (statusCode) {
    401, 403 -> resource(R.string.error_gradey_authentication)
    408 -> resource(R.string.error_request_timeout)
    429 -> resource(R.string.error_rate_limited)
    else -> resource(R.string.error_gradey_http, statusCode)
}

private fun GradeyAIException.toUserFacingError(): UserFacingError = when (kind) {
    GradeyAIErrorKind.NOT_CONFIGURED -> resource(R.string.error_ai_not_configured)
    GradeyAIErrorKind.INVALID_PROMPT -> resource(R.string.error_ai_invalid_prompt)
    GradeyAIErrorKind.REQUEST_TOO_LARGE -> resource(R.string.error_ai_request_too_large)
    GradeyAIErrorKind.UNAUTHENTICATED -> resource(R.string.error_gradey_authentication)
    GradeyAIErrorKind.NO_CONTEXT -> resource(R.string.error_ai_no_context)
    GradeyAIErrorKind.LIMIT_REACHED -> resource(R.string.error_ai_limit_reached)
    GradeyAIErrorKind.TRANSPORT -> resource(R.string.error_connection_failed)
    GradeyAIErrorKind.MALFORMED_RESPONSE -> resource(R.string.error_ai_malformed_response)
    GradeyAIErrorKind.SERVER -> resource(R.string.error_ai_server)
}

private fun GradeyAIContextException.toUserFacingError(): UserFacingError = when (error) {
    GradeyAIContextError.NO_SCHOOL_ACCOUNT -> resource(R.string.error_ai_no_school_account)
    GradeyAIContextError.NO_CONTEXT_AVAILABLE -> resource(R.string.error_ai_no_context)
    GradeyAIContextError.SCHOOL_ACCOUNT_CHANGED -> resource(R.string.error_ai_school_changed)
}

private fun StravaCZException.toUserFacingError(): UserFacingError = when (kind) {
    StravaCZErrorKind.AUTHENTICATION -> resource(R.string.error_meals_authentication)
    StravaCZErrorKind.INSUFFICIENT_BALANCE -> resource(R.string.error_meals_insufficient_balance)
    StravaCZErrorKind.DECODING -> resource(R.string.error_meals_decoding)
    StravaCZErrorKind.INVALID_RESPONSE -> resource(R.string.error_meals_invalid_response)
    StravaCZErrorKind.HTTP -> statusCode
        ?.let { resource(R.string.error_meals_http, it) }
        ?: resource(R.string.error_meals_server)
    StravaCZErrorKind.TRANSPORT -> resource(R.string.error_connection_failed)
}

private fun StravaCZAppException.toUserFacingError(): UserFacingError = when (error) {
    StravaCZAppError.NOT_LOGGED_IN -> resource(R.string.error_meals_not_connected)
    StravaCZAppError.MISSING_FIELDS -> resource(R.string.error_meals_missing_fields)
    StravaCZAppError.MEAL_NOT_FOUND -> resource(R.string.error_meal_not_found)
    StravaCZAppError.MEAL_NOT_MODIFIABLE -> resource(R.string.error_meal_not_modifiable)
}

private fun purchaseError(code: PurchasesErrorCode): UserFacingError = when (code) {
    PurchasesErrorCode.PurchaseCancelledError -> resource(R.string.error_purchase_cancelled)
    PurchasesErrorCode.PaymentPendingError -> resource(R.string.error_purchase_pending)
    PurchasesErrorCode.NetworkError -> resource(R.string.error_purchase_network)
    PurchasesErrorCode.PurchaseNotAllowedError,
    PurchasesErrorCode.IneligibleError,
    PurchasesErrorCode.InsufficientPermissionsError,
    -> resource(R.string.error_purchase_not_allowed)
    PurchasesErrorCode.ProductNotAvailableForPurchaseError ->
        resource(R.string.error_purchase_option_unavailable)
    PurchasesErrorCode.ProductAlreadyPurchasedError -> resource(R.string.error_purchase_already_owned)
    PurchasesErrorCode.OperationAlreadyInProgressError -> resource(R.string.error_purchase_in_progress)
    PurchasesErrorCode.InvalidCredentialsError,
    PurchasesErrorCode.InvalidAppUserIdError,
    PurchasesErrorCode.InvalidAppleSubscriptionKeyError,
    PurchasesErrorCode.ConfigurationError,
    -> resource(R.string.error_purchase_not_configured)
    PurchasesErrorCode.PurchaseInvalidError,
    PurchasesErrorCode.ReceiptAlreadyInUseError,
    PurchasesErrorCode.InvalidReceiptError,
    PurchasesErrorCode.MissingReceiptFileError,
    PurchasesErrorCode.InvalidSubscriberAttributesError,
    PurchasesErrorCode.EmptySubscriberAttributesError,
    PurchasesErrorCode.SignatureVerificationError,
    -> resource(R.string.error_purchase_invalid)
    PurchasesErrorCode.StoreProblemError,
    PurchasesErrorCode.UnexpectedBackendResponseError,
    PurchasesErrorCode.UnknownBackendError,
    PurchasesErrorCode.CustomerInfoError,
    -> resource(R.string.error_purchase_server)
    PurchasesErrorCode.LogOutWithAnonymousUserError -> resource(R.string.error_purchase_sign_in_required)
    PurchasesErrorCode.UnsupportedError -> resource(R.string.error_purchase_not_allowed)
    PurchasesErrorCode.UnknownError -> resource(R.string.error_purchase_failed)
}

private fun Throwable.causalChain(): List<Throwable> {
    val seen = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())
    val result = mutableListOf<Throwable>()
    var current: Throwable? = this
    while (current != null && result.size < MAX_CAUSE_DEPTH && seen.add(current)) {
        result += current
        current = current.cause
    }
    return result
}

private fun resource(@StringRes messageRes: Int, vararg arguments: Any): UserFacingError =
    UserFacingError(messageRes, arguments.toList())

private const val MAX_CAUSE_DEPTH = 16
