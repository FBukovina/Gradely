package com.bukovinafilip.gradey

import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import androidx.credentials.exceptions.NoCredentialException
import com.bukovinafilip.gradey.domain.GradeyAIContextError
import com.bukovinafilip.gradey.domain.GradeyAIContextException
import com.bukovinafilip.gradey.domain.GradeyAIErrorKind
import com.bukovinafilip.gradey.domain.GradeyAIException
import com.bukovinafilip.gradey.domain.GradeySessionExpiredException
import com.bukovinafilip.gradey.domain.InvalidDemoAccountCredentialsException
import com.bukovinafilip.gradey.domain.SchoolSessionExpiredException
import com.bukovinafilip.gradey.domain.StravaCZAppError
import com.bukovinafilip.gradey.domain.StravaCZAppException
import com.bukovinafilip.gradey.domain.StravaCZErrorKind
import com.bukovinafilip.gradey.domain.StravaCZException
import com.bukovinafilip.gradey.network.BakalariAuthenticationException
import com.bukovinafilip.gradey.network.BakalariDecodingException
import com.bukovinafilip.gradey.network.BakalariHttpException
import com.bukovinafilip.gradey.network.BakalariOfflineException
import com.bukovinafilip.gradey.network.GradeyApiException
import com.bukovinafilip.gradey.network.GradeyFunctionException
import com.google.common.truth.Truth.assertThat
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import kotlinx.serialization.SerializationException
import org.junit.Test

class UserFacingErrorTest {
    @Test
    fun sessionAndAuthenticationFailuresHaveSpecificResources() {
        assertMapsTo(SchoolSessionExpiredException(), R.string.school_session_expired)
        assertMapsTo(GradeySessionExpiredException(), R.string.error_gradey_session_expired)
        assertMapsTo(
            BakalariAuthenticationException(401, "<html>password=secret</html>"),
            R.string.error_school_authentication,
        )
        assertMapsTo(
            GradeyApiException(401, "{\"token\":\"secret\"}"),
            R.string.error_gradey_authentication,
        )
    }

    @Test
    fun bakalariFailuresKeepCategoryAndOnlySafeStatusCode() {
        assertMapsTo(
            BakalariOfflineException(UnknownHostException("private.school.example")),
            R.string.error_offline,
        )
        assertMapsTo(
            BakalariDecodingException(SerializationException("access_token=secret")),
            R.string.error_school_decoding,
        )

        val http = BakalariHttpException(503, "<html>backend stack trace</html>").toUserFacingError()
        assertThat(http.messageRes).isEqualTo(R.string.error_school_http)
        assertThat(http.formatArguments).containsExactly(503)
        assertThat(http.formatArguments.joinToString()).doesNotContain("backend")
    }

    @Test
    fun gradeyFunctionsRetainOperationCategoryWithoutServerText() {
        assertMapsTo(
            GradeyFunctionException(
                function = "grade-history",
                statusCode = 500,
                code = "internal_secret_code",
                message = "<html>token=secret</html>",
            ),
            R.string.error_grade_history,
        )
        assertMapsTo(
            GradeyFunctionException("link-school-account", 500, "secret", "private body"),
            R.string.error_linked_account,
        )
        assertMapsTo(
            GradeyFunctionException("request-data-export", 500, null, "private body"),
            R.string.error_data_export,
        )
        assertMapsTo(
            GradeyFunctionException("delete-account", 500, null, "private body"),
            R.string.error_account_deletion,
        )
        assertMapsTo(
            GradeyFunctionException("unknown", 429, null, "private body"),
            R.string.error_rate_limited,
        )
    }

    @Test
    fun aiFailuresRetainMeaningfulKinds() {
        val cases = mapOf(
            GradeyAIErrorKind.NOT_CONFIGURED to R.string.error_ai_not_configured,
            GradeyAIErrorKind.INVALID_PROMPT to R.string.error_ai_invalid_prompt,
            GradeyAIErrorKind.REQUEST_TOO_LARGE to R.string.error_ai_request_too_large,
            GradeyAIErrorKind.UNAUTHENTICATED to R.string.error_gradey_authentication,
            GradeyAIErrorKind.NO_CONTEXT to R.string.error_ai_no_context,
            GradeyAIErrorKind.LIMIT_REACHED to R.string.error_ai_limit_reached,
            GradeyAIErrorKind.TRANSPORT to R.string.error_connection_failed,
            GradeyAIErrorKind.MALFORMED_RESPONSE to R.string.error_ai_malformed_response,
            GradeyAIErrorKind.SERVER to R.string.error_ai_server,
        )
        cases.forEach { (kind, expected) ->
            assertMapsTo(
                GradeyAIException(kind, "<html>authorization: bearer secret</html>"),
                expected,
            )
        }
        assertMapsTo(
            GradeyAIContextException(GradeyAIContextError.SCHOOL_ACCOUNT_CHANGED),
            R.string.error_ai_school_changed,
        )
    }

    @Test
    fun mealsFailuresRetainMeaningfulKinds() {
        assertMapsTo(
            StravaCZException(StravaCZErrorKind.AUTHENTICATION, "password=secret"),
            R.string.error_meals_authentication,
        )
        assertMapsTo(
            StravaCZException(StravaCZErrorKind.INSUFFICIENT_BALANCE, "private balance"),
            R.string.error_meals_insufficient_balance,
        )
        assertMapsTo(
            StravaCZAppException(StravaCZAppError.MEAL_NOT_MODIFIABLE),
            R.string.error_meal_not_modifiable,
        )
    }

    @Test
    fun credentialAndAppAuthFailuresAreTyped() {
        assertMapsTo(
            GetCredentialCancellationException("private provider message"),
            R.string.error_google_sign_in_cancelled,
        )
        assertMapsTo(NoCredentialException("private provider message"), R.string.error_google_sign_in_no_account)
        assertMapsTo(
            GetCredentialProviderConfigurationException("client secret"),
            R.string.error_google_sign_in_unavailable,
        )
        assertMapsTo(
            AppAuthException(AppAuthError.GOOGLE_NOT_CONFIGURED),
            R.string.google_sign_in_not_configured,
        )
    }

    @Test
    fun revenueCatFailuresKeepPurchaseCategoryWithoutSdkMessage() {
        assertMapsTo(
            PurchasesException(PurchasesError(PurchasesErrorCode.NetworkError, "api-key=secret")),
            R.string.error_purchase_network,
        )
        assertMapsTo(
            PurchasesException(PurchasesError(PurchasesErrorCode.PurchaseNotAllowedError, "private")),
            R.string.error_purchase_not_allowed,
        )
        assertMapsTo(
            SupportServiceException(SupportServiceError.OPTION_UNAVAILABLE),
            R.string.error_purchase_option_unavailable,
        )
    }

    @Test
    fun standardTransportAndDecodingCausesAreRecognizedThroughWrappers() {
        assertMapsTo(RuntimeException("wrapper", UnknownHostException("secret-host")), R.string.error_offline)
        assertMapsTo(RuntimeException("wrapper", SocketTimeoutException("secret-host")), R.string.error_request_timeout)
        assertMapsTo(
            RuntimeException("wrapper", SerializationException("token=secret")),
            R.string.error_unreadable_response,
        )
    }

    @Test
    fun arbitraryMessagesAndDemoCredentialsAreNeverRendered() {
        val raw = RuntimeException("<html>password=hunter2 access_token=secret</html>").toUserFacingError()
        assertThat(raw.messageRes).isEqualTo(R.string.generic_error)
        assertThat(raw.formatArguments).isEmpty()
        assertMapsTo(InvalidDemoAccountCredentialsException(), R.string.error_invalid_demo_credentials)
    }

    private fun assertMapsTo(error: Throwable, expectedResource: Int) {
        val mapped = error.toUserFacingError()
        assertThat(mapped.messageRes).isEqualTo(expectedResource)
        assertThat(mapped.formatArguments).isEmpty()
    }
}
