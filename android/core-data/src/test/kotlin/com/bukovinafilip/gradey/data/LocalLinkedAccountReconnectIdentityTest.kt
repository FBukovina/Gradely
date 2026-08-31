package com.bukovinafilip.gradey.data

import com.bukovinafilip.gradey.model.LinkedAccountProvider
import com.bukovinafilip.gradey.model.LinkedAccountStatus
import com.bukovinafilip.gradey.model.LinkedSchoolAccount
import com.bukovinafilip.gradey.model.StoredSession
import com.bukovinafilip.gradey.model.UserResponse
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.ListSerializer
import org.junit.Test

class LocalLinkedAccountReconnectIdentityTest {
    @Test
    fun `unproven reconnect identity cannot write the local account cache`() = runTest {
        val original = account()
        val preferences = LinkedAccountPreferences(listOf(original))
        val repository = LocalLinkedAccountRepository(SecureJsonStore(preferences, GradeyJson))
        val candidates = listOf(
            null,
            UserResponse("Student", userUID = null),
            UserResponse("Student", userUID = " "),
            UserResponse("Another student", userUID = "another-provider-user"),
        )

        candidates.forEach { candidate ->
            val failure = runCatching {
                repository.reconnectSchoolAccount(
                    accountID = original.id,
                    session = session(),
                    user = candidate,
                )
            }.exceptionOrNull()

            assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        }

        assertThat(preferences.commits).isEmpty()
        assertThat(repository.localAccounts()).containsExactly(original)
    }

    @Test
    fun `matching canonical identity permits one exact local cache replacement`() = runTest {
        val original = account()
        val preferences = LinkedAccountPreferences(listOf(original))
        val repository = LocalLinkedAccountRepository(SecureJsonStore(preferences, GradeyJson))

        val updated = repository.reconnectSchoolAccount(
            accountID = original.id,
            session = session(),
            user = UserResponse("Updated student", userUID = " provider-user "),
        )

        assertThat(updated.providerUserID).isEqualTo("provider-user")
        assertThat(updated.displayName).isEqualTo("Updated student")
        assertThat(preferences.commits).hasSize(1)
        assertThat(repository.localAccounts()).containsExactly(updated)
    }

    private fun account() = LinkedSchoolAccount(
        id = "school",
        provider = LinkedAccountProvider.BAKALARI,
        providerUserID = "provider-user",
        displayName = "Student",
        schoolName = "School",
        status = LinkedAccountStatus.ACTION_REQUIRED,
    )

    private fun session() = StoredSession(
        accessToken = "access",
        refreshToken = "refresh",
        tokenType = "Bearer",
        expiresAtEpochMillis = Long.MAX_VALUE,
        baseURL = "https://school.example.cz",
    )

    private class LinkedAccountPreferences(accounts: List<LinkedSchoolAccount>) : SecureJsonPreferences {
        private val values = mutableMapOf(
            LINKED_ACCOUNTS_KEY to GradeyJson.encodeToString(
                ListSerializer(LinkedSchoolAccount.serializer()),
                accounts,
            ),
        )
        val commits = mutableListOf<Map<String, String?>>()

        override fun getString(key: String, defaultValue: String?): String? = values[key] ?: defaultValue

        override fun commit(changes: Map<String, String?>): Boolean {
            commits += changes.toMap()
            changes.forEach { (key, value) ->
                if (value == null) values.remove(key) else values[key] = value
            }
            return true
        }
    }

    private companion object {
        const val LINKED_ACCOUNTS_KEY = "gradey.linkedAccounts.v1"
    }
}
