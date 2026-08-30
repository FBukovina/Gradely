package com.bukovinafilip.gradey.data

import android.content.Context
import com.bukovinafilip.gradey.domain.DevicePushTokenClient
import com.bukovinafilip.gradey.domain.GradeyAuthRepository
import com.bukovinafilip.gradey.domain.GradeyAIRepository
import com.bukovinafilip.gradey.domain.GradeyAIContextBuilding
import com.bukovinafilip.gradey.domain.GradeyHistoryRepository
import com.bukovinafilip.gradey.domain.LinkedAccountRepository
import com.bukovinafilip.gradey.domain.SchoolRepository
import com.bukovinafilip.gradey.domain.SchoolDirectoryRepository
import com.bukovinafilip.gradey.domain.StravaCZRepository
import com.bukovinafilip.gradey.network.BakalariNetworkClient
import com.bukovinafilip.gradey.network.BakalariSchoolDirectoryClient
import com.bukovinafilip.gradey.network.DemoAwareBakalariClient
import com.bukovinafilip.gradey.network.GradeyJson
import com.bukovinafilip.gradey.network.SupabaseConfiguration
import com.bukovinafilip.gradey.network.SupabaseDevicePushTokenClient
import com.bukovinafilip.gradey.network.SupabaseGradeyAuthRepository
import com.bukovinafilip.gradey.network.SupabaseGradeyHistoryRepository
import com.bukovinafilip.gradey.network.SupabaseLinkedAccountRepository
import com.bukovinafilip.gradey.network.StravaCZNetworkClient
import kotlinx.serialization.builtins.ListSerializer

data class AndroidGradeyConfig(
    val supabaseUrl: String,
    val supabaseAnonKey: String,
    val googleWebClientId: String,
    val revenueCatAndroidKey: String,
)

interface GradeyCacheOwner {
    val gradeyCache: RoomGradeyCache?
}

class AndroidGradeyGraph private constructor(
    val schoolRepository: SchoolRepository,
    val schoolDirectoryRepository: SchoolDirectoryRepository,
    val gradeyAuthRepository: GradeyAuthRepository,
    val linkedAccountRepository: LinkedAccountRepository,
    val historyRepository: GradeyHistoryRepository,
    val devicePushTokenClient: DevicePushTokenClient,
    val gradeyAIRepository: GradeyAIRepository,
    val gradeyAIContextBuilder: GradeyAIContextBuilding,
    val stravaCZRepository: StravaCZRepository,
    val cache: RoomGradeyCache?,
    val ageAttestationStore: AgeAttestationStore,
    val guestModeStore: GradeyGuestModeStore,
    val onboardingProgressStore: OnboardingProgressStore,
    val appLanguageStore: AppLanguageStore,
    val mealsTabPreferenceStore: MealsTabPreferenceStore,
    val notificationPreferencesStore: NotificationPreferencesStore,
    val pushRegistrationStore: PushRegistrationStore,
    val isGradeyCloudConfigured: Boolean,
    val googleWebClientId: String,
) {
    companion object {
        fun create(context: Context, config: AndroidGradeyConfig): AndroidGradeyGraph {
            val database = buildGradeyDatabase(context)
            val cache = RoomGradeyCache(database.cacheEntries(), GradeyJson)
            val schoolSecureStore = SecureJsonStore(context, "gradey-school-secrets", GradeyJson)
            val authSecureStore = SecureJsonStore(context, "gradey-auth-secrets", GradeyJson)
            val linkedAccountStore = SecureJsonStore(context, "gradey-linked-accounts", GradeyJson)
            val stravaCZSecureStore = SecureJsonStore(context, "gradey-stravacz-secrets", GradeyJson)
            val sessionStore = SchoolSessionStore(schoolSecureStore)
            val supabase = SupabaseConfiguration(config.supabaseUrl, config.supabaseAnonKey)

            val authRepository = if (supabase.isConfigured) {
                SupabaseGradeyAuthRepository(
                    configuration = supabase,
                    sessionStore = {
                        if (it == null) {
                            authSecureStore.clear("gradey.auth.session")
                        } else {
                            authSecureStore.save("gradey.auth.session", it, com.bukovinafilip.gradey.model.GradeyAuthSession.serializer())
                        }
                    },
                    sessionLoader = {
                        authSecureStore.loadOrClearInvalid(
                            "gradey.auth.session",
                            com.bukovinafilip.gradey.model.GradeyAuthSession.serializer(),
                        )
                    },
                )
            } else {
                LocalOnlyGradeyAuthRepository()
            }
            val linkedAccountSerializer = ListSerializer(
                com.bukovinafilip.gradey.model.LinkedSchoolAccount.serializer(),
            )
            val linkedAccountRepository = if (supabase.isConfigured) {
                SupabaseLinkedAccountRepository(
                    configuration = supabase,
                    authRepository = authRepository,
                    accountStore = { accounts ->
                        if (accounts == null) {
                            linkedAccountStore.clear("gradey.linkedAccounts.v1")
                            linkedAccountStore.clear("linked.accounts.v1")
                        } else {
                            linkedAccountStore.save(
                                "gradey.linkedAccounts.v1",
                                accounts,
                                linkedAccountSerializer,
                            )
                            linkedAccountStore.clear("linked.accounts.v1")
                        }
                    },
                    accountLoader = {
                        linkedAccountStore.loadOrClearInvalid(
                            "gradey.linkedAccounts.v1",
                            linkedAccountSerializer,
                        ) ?: linkedAccountStore.loadOrClearInvalid(
                            "linked.accounts.v1",
                            linkedAccountSerializer,
                        )?.also { accounts ->
                            linkedAccountStore.save(
                                "gradey.linkedAccounts.v1",
                                accounts,
                                linkedAccountSerializer,
                            )
                            linkedAccountStore.clear("linked.accounts.v1")
                        }.orEmpty()
                    },
                )
            } else {
                LocalLinkedAccountRepository(linkedAccountStore)
            }

            val schoolRepository = AndroidSchoolRepository(
                bakalariClient = DemoAwareBakalariClient(BakalariNetworkClient()),
                sessionStore = sessionStore,
                cache = cache,
            )
            val historyRepository = if (supabase.isConfigured) {
                CachedGradeyHistoryRepository(
                    remote = SupabaseGradeyHistoryRepository(supabase, authRepository),
                    cache = cache,
                )
            } else {
                EmptyGradeyHistoryRepository()
            }

            return AndroidGradeyGraph(
                schoolRepository = schoolRepository,
                schoolDirectoryRepository = AndroidSchoolDirectoryRepository(
                    client = BakalariSchoolDirectoryClient(),
                    storage = RoomSchoolDirectoryStorage(cache),
                ),
                gradeyAuthRepository = authRepository,
                linkedAccountRepository = linkedAccountRepository,
                historyRepository = historyRepository,
                devicePushTokenClient = if (supabase.isConfigured) {
                    SupabaseDevicePushTokenClient(supabase)
                } else {
                    UnavailableDevicePushTokenClient()
                },
                gradeyAIRepository = FirebaseGradeyAIRepository(context, authRepository),
                gradeyAIContextBuilder = AndroidGradeyAIContextBuilder(
                    schoolRepository = schoolRepository,
                    historyRepository = historyRepository,
                    scopeHasher = GradeyAISchoolScopeHasher(context),
                ),
                stravaCZRepository = AndroidStravaCZRepository(
                    client = StravaCZNetworkClient(),
                    sessionStore = StravaCZSessionStore(stravaCZSecureStore),
                    cache = cache,
                ),
                cache = cache,
                ageAttestationStore = AgeAttestationStore(context),
                guestModeStore = GradeyGuestModeStore(context),
                onboardingProgressStore = OnboardingProgressStore(context, GradeyJson),
                appLanguageStore = AppLanguageStore(context),
                mealsTabPreferenceStore = MealsTabPreferenceStore(context),
                notificationPreferencesStore = NotificationPreferencesStore(context, GradeyJson),
                pushRegistrationStore = PushRegistrationStore(context),
                isGradeyCloudConfigured = supabase.isConfigured,
                googleWebClientId = config.googleWebClientId,
            )
        }
    }
}
