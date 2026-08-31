package com.bukovinafilip.gradey.domain

import com.bukovinafilip.gradey.model.AbsenceResponse
import com.bukovinafilip.gradey.model.CachedSchoolDirectory
import com.bukovinafilip.gradey.model.DashboardData
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.GradeyAccountSettingsSnapshot
import com.bukovinafilip.gradey.model.GradeyAIConsent
import com.bukovinafilip.gradey.model.GradeyAIConversation
import com.bukovinafilip.gradey.model.GradeyAIConversationDetail
import com.bukovinafilip.gradey.model.GradeyAIContextSnapshot
import com.bukovinafilip.gradey.model.GradeyAIStatus
import com.bukovinafilip.gradey.model.GradeyAIStreamEvent
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.LinkedSchoolAccountActivation
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import com.bukovinafilip.gradey.model.MarksResponse
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.model.SchoolProvider
import com.bukovinafilip.gradey.model.SchoolDirectoryMunicipality
import com.bukovinafilip.gradey.model.SchoolDirectorySchool
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StravaCZMeal
import com.bukovinafilip.gradey.model.StravaCZMenu
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.model.Subject
import com.bukovinafilip.gradey.model.TimetableWeek
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow

interface BakalariClient {
    suspend fun login(baseURL: String, username: String, password: String): com.bukovinafilip.gradey.model.LoginResponse
    suspend fun refreshToken(baseURL: String, refreshToken: String): com.bukovinafilip.gradey.model.LoginResponse
    suspend fun fetchMarks(baseURL: String, accessToken: String): MarksResponse
    suspend fun fetchAbsences(baseURL: String, accessToken: String): AbsenceResponse
    suspend fun fetchUser(baseURL: String, accessToken: String): com.bukovinafilip.gradey.model.UserResponse
    suspend fun fetchTimetable(baseURL: String, accessToken: String, date: String): com.bukovinafilip.gradey.model.TimetableResponse
    suspend fun predictSubject(baseURL: String, accessToken: String, subject: Subject, markText: String, weight: Int): Subject
}

interface SchoolDirectoryClient {
    suspend fun fetchMunicipalities(): List<SchoolDirectoryMunicipality>
    suspend fun fetchSchools(municipalityName: String): List<SchoolDirectorySchool>
}

interface SchoolDirectoryRepository {
    suspend fun loadCachedDirectory(): CachedSchoolDirectory?
    suspend fun refreshDirectory(): List<SchoolDirectorySchool>
}

/**
 * Identifies the current Gradey-cloud ownership boundary for mutations of the
 * locally retained school session.
 *
 * Tokens are deliberately opaque to callers. A [SchoolRepository]
 * implementation decides whether a token is still current when the mutation
 * reaches its atomic commit boundary.
 */
data class SchoolCloudMutationToken(
    val epoch: Long,
)

data class SchoolCloudInvalidationResult(
    val previousLinkedAccountID: String?,
    val retainedSession: StoredSession?,
)

data class AuthenticatedSchoolSessionCandidate(
    val session: StoredSession,
    val dashboard: DashboardData,
    val sessionGeneration: Long,
)

interface SchoolRepository {
    suspend fun bootstrapSession(): StoredSession?
    suspend fun currentStoredSession(): StoredSession?
    suspend fun login(schoolURL: String, username: String, password: String): StoredSession
    suspend fun login(
        schoolURL: String,
        username: String,
        password: String,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession = login(schoolURL, username, password)
    suspend fun authenticateSchoolSessionCandidate(
        schoolURL: String,
        username: String,
        password: String,
        cloudMutationToken: SchoolCloudMutationToken,
    ): AuthenticatedSchoolSessionCandidate
    suspend fun promoteAuthenticatedSchoolSessionCandidate(
        candidate: AuthenticatedSchoolSessionCandidate,
        account: LinkedSchoolAccount,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession
    suspend fun restoreSession(session: StoredSession): StoredSession
    suspend fun activateLinkedSchoolAccount(session: StoredSession): StoredSession
    suspend fun activateLinkedSchoolAccount(
        session: StoredSession,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession = activateLinkedSchoolAccount(session)
    suspend fun associateCurrentSession(account: LinkedSchoolAccount): StoredSession
    suspend fun associateCurrentSession(
        account: LinkedSchoolAccount,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession = associateCurrentSession(account)
    suspend fun disassociateCurrentSession(accountID: String): StoredSession?
    suspend fun disassociateCurrentSession(
        accountID: String,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession? = disassociateCurrentSession(accountID)
    suspend fun captureSchoolCloudMutationToken(): SchoolCloudMutationToken =
        SchoolCloudMutationToken(epoch = 0L)
    suspend fun invalidateSchoolCloudMutationsAndDisassociate(): SchoolCloudInvalidationResult {
        val current = currentStoredSession()
        val accountID = current?.linkedAccountID
        val retained = if (accountID == null) current else disassociateCurrentSession(accountID)
        return SchoolCloudInvalidationResult(
            previousLinkedAccountID = accountID,
            retainedSession = retained,
        )
    }
    suspend fun restoreSessionIfCurrentCandidate(
        candidate: StoredSession,
        previous: StoredSession?,
        cloudMutationToken: SchoolCloudMutationToken,
    ): StoredSession? {
        val current = currentStoredSession()
        if (current != candidate) return current
        if (previous != null) return restoreSession(previous)
        logout()
        return null
    }
    suspend fun logout()
    suspend fun clearLocalCaches() = Unit
    suspend fun clearNextLessonSnapshotIfSignedOut(): Boolean = currentStoredSession() == null
    suspend fun loadCachedDashboard(): DashboardData?
    suspend fun loadCachedAbsence(): AbsenceResponse?
    suspend fun loadDashboard(forceRefresh: Boolean = false): DashboardData
    suspend fun loadAbsence(forceRefresh: Boolean = false): AbsenceResponse
    suspend fun resolveAbsenceSubjects(
        response: AbsenceResponse,
        onProgress: suspend (AbsenceSubjectResolutionProgress) -> Unit = {},
    ): AbsenceSubjectResolution
    suspend fun saveManualAbsenceLessonSelections(selections: Map<String, Set<String>>)
    suspend fun loadAbsencePredictionLessons(on: String): List<AbsenceLessonCandidate>
    suspend fun loadCachedTimetable(weekContaining: String): TimetableWeek?
    suspend fun loadTimetable(weekContaining: String): TimetableWeek
    suspend fun predictSubjectAverage(subject: Subject, markText: String, weight: Int): Double?
}

class SchoolSessionExpiredException(
    cause: Throwable? = null,
) : IllegalStateException(
    "Your Bakaláři session expired. Please reconnect your school account.",
    cause,
)

class GradeySessionExpiredException(
    cause: Throwable? = null,
) : IllegalStateException(
    "Your Gradey ID session expired. Please sign in again.",
    cause,
)

class GradeyIdentityChangedException : CancellationException(
    "The Gradey identity changed while a request was running.",
)

interface GradeyAuthRepository {
    suspend fun bootstrapSession(): GradeyAuthSession?
    suspend fun validSession(): GradeyAuthSession
    suspend fun refreshAccount(): GradeyAccount
    suspend fun updateFullName(fullName: String): GradeyAccount
    suspend fun signInWithGoogle(idToken: String, accessToken: String? = null, fullName: String? = null): GradeyAuthSession
    /**
     * Atomically removes the durable local session and returns the exact session
     * that may still be revoked remotely. Implementations must serialize this
     * with token refresh and sign-in so stale auth work cannot restore it.
     */
    suspend fun takeLocalSessionForSignOut(): GradeyAuthSession? {
        val session = bootstrapSession()
        signOut()
        return session
    }

    /**
     * Best-effort remote cleanup for a session already removed locally.
     * The default is intentionally empty because legacy implementations perform
     * their remote cleanup inside [signOut].
     */
    suspend fun revokeSignedOutSession(session: GradeyAuthSession) = Unit

    suspend fun signOut()
}

interface LinkedAccountRepository {
    suspend fun localAccounts(): List<LinkedSchoolAccount>
    suspend fun refreshAccounts(): GradeyAccountSettingsSnapshot
    suspend fun linkSchoolAccount(session: StoredSession, user: com.bukovinafilip.gradey.model.UserResponse?): LinkedSchoolAccount
    suspend fun linkStravaCZAccount(session: StravaCZStoredSession): LinkedSchoolAccount
    suspend fun activateSchoolAccount(accountID: String): LinkedSchoolAccountActivation
    suspend fun reconnectSchoolAccount(
        accountID: String,
        session: StoredSession,
        user: com.bukovinafilip.gradey.model.UserResponse?,
    ): LinkedSchoolAccount
    suspend fun updateNotificationsEnabled(accountID: String, enabled: Boolean): LinkedSchoolAccount
    suspend fun unlinkAccount(accountID: String)
    suspend fun unlinkAccountForSignedOutSession(
        accountID: String,
        session: GradeyAuthSession,
    ) = Unit
    suspend fun clearLocalAccounts()
}

interface GradeyHistoryRepository {
    suspend fun loadCachedGradeHistory(accountID: String?): GradeHistoryResponse? = null
    suspend fun gradeHistory(accountID: String?, days: Int? = 90): GradeHistoryResponse
    suspend fun clearCachedGradeHistory(accountID: String?) = Unit
    suspend fun clearAllCachedGradeHistory() = Unit
}

interface DevicePushTokenClient {
    suspend fun registerDeviceToken(token: String, platform: String, environment: String, gradeySession: GradeyAuthSession)
    suspend fun updateNotificationPreferences(preferences: NotificationPreferences, gradeySession: GradeyAuthSession)
    suspend fun requestDataExport(gradeySession: GradeyAuthSession): String
    suspend fun deleteAccount(gradeySession: GradeyAuthSession)
}

interface GradeyAIRepository {
    val isConfigured: Boolean

    suspend fun loadStatus(): GradeyAIStatus
    suspend fun acceptConsent(): GradeyAIConsent
    suspend fun revokeConsent()
    suspend fun listConversations(schoolScope: String): List<GradeyAIConversation>
    suspend fun createConversation(schoolScope: String, title: String?): GradeyAIConversation
    suspend fun loadConversation(id: String): GradeyAIConversationDetail
    suspend fun deleteConversation(id: String)
    suspend fun deleteAllConversations(schoolScope: String)
    fun streamReply(
        conversationID: String,
        clientMessageID: String,
        text: String,
        context: GradeyAIContextSnapshot,
        locale: String,
    ): Flow<GradeyAIStreamEvent>
}

enum class GradeyAIErrorKind {
    NOT_CONFIGURED,
    INVALID_PROMPT,
    REQUEST_TOO_LARGE,
    UNAUTHENTICATED,
    NO_CONTEXT,
    LIMIT_REACHED,
    TRANSPORT,
    MALFORMED_RESPONSE,
    SERVER,
}

class GradeyAIException(
    val kind: GradeyAIErrorKind,
    message: String,
    val retryable: Boolean = false,
    val serverCode: String? = null,
    cause: Throwable? = null,
) : IllegalStateException(message, cause)

object GradeyAIErrorClassifier {
    fun server(
        code: String,
        message: String,
        retryable: Boolean,
        cause: Throwable? = null,
    ): GradeyAIException {
        val normalizedCode = code.lowercase()
        val normalizedMessage = message.lowercase()
        val kind = when {
            normalizedCode in AuthenticationCodes || "unauthenticated" in normalizedMessage -> {
                GradeyAIErrorKind.UNAUTHENTICATED
            }
            normalizedCode in ContextCodes ||
                ("context" in normalizedMessage && ("missing" in normalizedMessage || "unavailable" in normalizedMessage)) -> {
                GradeyAIErrorKind.NO_CONTEXT
            }
            normalizedCode in LimitCodes -> {
                GradeyAIErrorKind.LIMIT_REACHED
            }
            normalizedCode in OversizeCodes || "too large" in normalizedMessage -> {
                GradeyAIErrorKind.REQUEST_TOO_LARGE
            }
            else -> GradeyAIErrorKind.SERVER
        }
        return GradeyAIException(
            kind = kind,
            message = message,
            retryable = retryable,
            serverCode = code,
            cause = cause,
        )
    }

    private val AuthenticationCodes = setOf("unauthenticated", "authentication_required", "auth_required")
    private val ContextCodes = setOf("no_context", "missing_context", "context_unavailable", "invalid_context")
    private val LimitCodes = setOf("over_limit", "daily_limit", "limit_reached")
    private val OversizeCodes = setOf("request_too_large", "payload_too_large", "context_too_large", "oversize")
}

interface GradeyAIContextBuilding {
    suspend fun currentSchoolScope(): String
    suspend fun cachedContext(): GradeyAIContextSnapshot?
    suspend fun refreshContext(): GradeyAIContextSnapshot
}

enum class GradeyAIContextError {
    NO_SCHOOL_ACCOUNT,
    NO_CONTEXT_AVAILABLE,
    SCHOOL_ACCOUNT_CHANGED,
}

class GradeyAIContextException(
    val error: GradeyAIContextError,
) : IllegalStateException(
    when (error) {
        GradeyAIContextError.NO_SCHOOL_ACCOUNT -> "Connect a Bakaláři account first."
        GradeyAIContextError.NO_CONTEXT_AVAILABLE -> "No school context is available for Gradey AI."
        GradeyAIContextError.SCHOOL_ACCOUNT_CHANGED -> "The active school changed while Gradey AI context was loading."
    },
)

interface StravaCZRepository {
    suspend fun bootstrapSession(): StravaCZStoredSession?
    suspend fun loadCachedMenu(): StravaCZMenu?
    suspend fun login(canteenNumber: String, username: String, password: String): StravaCZStoredSession
    suspend fun loadMenu(forceRefresh: Boolean = false): Pair<StravaCZStoredSession, StravaCZMenu>
    suspend fun setMeal(meal: StravaCZMeal, ordered: Boolean): Pair<StravaCZStoredSession, StravaCZMenu>
    /**
     * Atomically clears the local meals session/cache and returns the exact session that may
     * still be logged out remotely. Implementations should invalidate pending local commits.
     */
    suspend fun takeLocalSessionForSignOut(): StravaCZStoredSession? {
        val session = bootstrapSession()
        logout()
        return session
    }

    /** Best-effort remote cleanup for a session that is already absent locally. */
    suspend fun revokeSignedOutSession(session: StravaCZStoredSession) = Unit

    /** Compatibility local logout. This must not wait for remote session revocation. */
    suspend fun logout()
}

interface StravaCZClient {
    suspend fun login(canteenNumber: String, username: String, password: String): StravaCZStoredSession
    suspend fun fetchMenu(session: StravaCZStoredSession): StravaCZMenu
    suspend fun changeMealOrder(session: StravaCZStoredSession, mealID: Int, ordered: Boolean): Double?
    suspend fun saveOrders(session: StravaCZStoredSession): Double?
    suspend fun cancelOrderChanges(session: StravaCZStoredSession): Double?
    suspend fun logout(session: StravaCZStoredSession)
}

enum class StravaCZErrorKind {
    INVALID_RESPONSE,
    HTTP,
    AUTHENTICATION,
    INSUFFICIENT_BALANCE,
    DECODING,
    TRANSPORT,
}

class StravaCZException(
    val kind: StravaCZErrorKind,
    message: String,
    val statusCode: Int? = null,
    cause: Throwable? = null,
) : IllegalStateException(message, cause)

enum class StravaCZAppError(val messageText: String) {
    NOT_LOGGED_IN("Connect your Strava.cz account first."),
    MISSING_FIELDS("Enter the canteen number, username, and password."),
    MEAL_NOT_FOUND("That meal is no longer in the current menu."),
    MEAL_NOT_MODIFIABLE("This meal can no longer be changed."),
}

class StravaCZAppException(
    val error: StravaCZAppError,
) : IllegalStateException(error.messageText)
