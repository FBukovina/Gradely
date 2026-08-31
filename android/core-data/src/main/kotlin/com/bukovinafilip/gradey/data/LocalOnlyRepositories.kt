package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.domain.DevicePushTokenClient
import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.domain.GradeyHistoryRepository
import com.bukovinafilip.gradey.domain.LinkedAccountRepository
import com.bukovinafilip.gradey.domain.SchoolDirectoryNameResolver
import com.bukovinafilip.gradey.model.GradeyAuthSession
import com.bukovinafilip.gradey.model.GradeyAccount
import com.bukovinafilip.gradey.model.GradeyAccountSettingsSnapshot
import com.bukovinafilip.gradey.model.GradeHistoryResponse
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedSchoolAccountActivation
import com.bukovinafilip.gradey.model.NotificationPreferences
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.StravaCZStoredSession
import com.bukovinafilip.gradey.model.UserResponse
import kotlinx.serialization.builtins.ListSerializer
import java.util.UUID

class FeatureUnavailableException(message: String) : IllegalStateException(message)

class LocalOnlyGradeyAuthRepository : GradeyAuthRepository {
    override suspend fun bootstrapSession(): GradeyAuthSession? = null

    override suspend fun validSession(): GradeyAuthSession = unavailable()

    override suspend fun refreshAccount(): GradeyAccount = unavailable()

    override suspend fun updateFullName(fullName: String): GradeyAccount = unavailable()

    override suspend fun signInWithGoogle(
        idToken: String,
        accessToken: String?,
        fullName: String?,
    ): GradeyAuthSession = unavailable()

    override suspend fun signOut() = Unit

    private fun unavailable(): Nothing = throw FeatureUnavailableException(
        "Gradey ID is not configured in this build. You can still use Bakaláři locally.",
    )
}

class LocalLinkedAccountRepository(
    private val store: SecureJsonStore,
) : LinkedAccountRepository {
    private val serializer = ListSerializer(LinkedSchoolAccount.serializer())

    override suspend fun localAccounts(): List<LinkedSchoolAccount> =
        localAccountsBlocking()

    override suspend fun refreshAccounts(): GradeyAccountSettingsSnapshot =
        GradeyAccountSettingsSnapshot(linkedAccounts = localAccounts())

    override suspend fun linkSchoolAccount(
        session: StoredSession,
        user: UserResponse?,
    ): LinkedSchoolAccount {
        val account = LinkedSchoolAccount(
            id = session.linkedAccountID ?: UUID.randomUUID().toString(),
            provider = LinkedAccountProvider.from(session.provider),
            providerUserID = user?.userUID,
            displayName = user?.fullName ?: session.linkedAccountDisplayName ?: session.provider.displayName,
            schoolName = resolvedLocalLinkedSchoolName(user, session.linkedAccountSchoolName),
        )
        saveUpsert(account)
        return account
    }

    override suspend fun linkStravaCZAccount(session: StravaCZStoredSession): LinkedSchoolAccount {
        val existing = localAccounts().firstOrNull {
            it.provider == LinkedAccountProvider.STRAVA_CZ && it.providerUserID == session.username
        }
        val account = LinkedSchoolAccount(
            id = existing?.id ?: UUID.randomUUID().toString(),
            provider = LinkedAccountProvider.STRAVA_CZ,
            providerUserID = session.username,
            displayName = session.displayName,
            canteenName = session.canteenName,
            notificationsEnabled = false,
        )
        saveUpsert(account)
        return account
    }

    override suspend fun activateSchoolAccount(accountID: String): LinkedSchoolAccountActivation =
        throw FeatureUnavailableException("School account switching requires Gradey ID configuration.")

    override suspend fun reconnectSchoolAccount(
        accountID: String,
        session: StoredSession,
        user: UserResponse?,
    ): LinkedSchoolAccount {
        val existing = localAccounts().firstOrNull { it.id == accountID }
            ?: throw IllegalArgumentException("Linked school account was not found.")
        val updated = existing.copy(
            providerUserID = user?.userUID ?: existing.providerUserID,
            displayName = user?.fullName ?: existing.displayName,
            schoolName = resolvedLocalLinkedSchoolName(user, existing.schoolName),
        )
        saveUpsert(updated)
        return updated
    }

    override suspend fun updateNotificationsEnabled(accountID: String, enabled: Boolean): LinkedSchoolAccount {
        val existing = localAccounts().firstOrNull { it.id == accountID }
            ?: throw IllegalArgumentException("Linked school account was not found.")
        return existing.copy(notificationsEnabled = enabled).also(::saveUpsert)
    }

    override suspend fun unlinkAccount(accountID: String) {
        store.save(KEY, localAccounts().filterNot { it.id == accountID }, serializer)
    }

    override suspend fun clearLocalAccounts() {
        store.clear(KEY)
    }

    private fun saveUpsert(account: LinkedSchoolAccount) {
        val updated = localAccountsBlocking().filterNot { it.id == account.id } + account
        store.save(KEY, updated, serializer)
    }

    private fun localAccountsBlocking(): List<LinkedSchoolAccount> =
        store.load(KEY, serializer) ?: store.load(LEGACY_KEY, serializer)?.also { accounts ->
            store.save(KEY, accounts, serializer)
            store.clear(LEGACY_KEY)
        }.orEmpty()

    private companion object {
        const val KEY = "gradey.linkedAccounts.v1"
        const val LEGACY_KEY = "linked.accounts.v1"
    }
}

internal fun resolvedLocalLinkedSchoolName(user: UserResponse?, fallback: String?): String? =
    user?.displaySchoolName ?: SchoolDirectoryNameResolver.displayableName(fallback)

class EmptyGradeyHistoryRepository : GradeyHistoryRepository {
    override suspend fun gradeHistory(accountID: String?, days: Int?): GradeHistoryResponse = GradeHistoryResponse()
}

class UnavailableDevicePushTokenClient : DevicePushTokenClient {
    override suspend fun registerDeviceToken(
        token: String,
        platform: String,
        environment: String,
        gradeySession: GradeyAuthSession,
    ) = throw FeatureUnavailableException("Push registration requires Gradey ID configuration.")

    override suspend fun updateNotificationPreferences(
        preferences: NotificationPreferences,
        gradeySession: GradeyAuthSession,
    ) = throw FeatureUnavailableException("Notification preferences require Gradey ID configuration.")

    override suspend fun requestDataExport(
        gradeySession: GradeyAuthSession,
    ): String = throw FeatureUnavailableException("Data export requires Gradey ID configuration.")

    override suspend fun deleteAccount(
        gradeySession: GradeyAuthSession,
    ) = throw FeatureUnavailableException("Account deletion requires Gradey ID configuration.")
}
