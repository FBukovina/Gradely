package com.bukovinafilip.gradey.data

import android.content.Context
import androidx.room.Room
import com.bukovinafilip.gradey.domain.DevicePushTokenClient
import com.bukovinafilip.gradey.domain.GradeyAuthRepository
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
    val stravaCZRepository: StravaCZRepository,
    val cache: RoomGradeyCache?,
    val isGradeyCloudConfigured: Boolean,
    val googleWebClientId: String,
) {
    companion object {
        fun create(context: Context, config: AndroidGradeyConfig): AndroidGradeyGraph {
            val database = Room.databaseBuilder(context, GradeyDatabase::class.java, "gradey.db")
                .build()
            val cache = RoomGradeyCache(database.cacheEntries(), GradeyJson)
            val schoolSecureStore = SecureJsonStore(context, "gradey-school-secrets", GradeyJson)
            val authSecureStore = SecureJsonStore(context, "gradey-auth-secrets", GradeyJson)
            val linkedAccountStore = SecureJsonStore(context, "gradey-linked-accounts", GradeyJson)
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

            return AndroidGradeyGraph(
                schoolRepository = AndroidSchoolRepository(
                    bakalariClient = DemoAwareBakalariClient(BakalariNetworkClient()),
                    sessionStore = sessionStore,
                    cache = cache,
                ),
                schoolDirectoryRepository = AndroidSchoolDirectoryRepository(
                    client = BakalariSchoolDirectoryClient(),
                    storage = RoomSchoolDirectoryStorage(cache),
                ),
                gradeyAuthRepository = authRepository,
                linkedAccountRepository = LocalLinkedAccountRepository(linkedAccountStore),
                historyRepository = EmptyGradeyHistoryRepository(),
                devicePushTokenClient = if (supabase.isConfigured) {
                    SupabaseDevicePushTokenClient(supabase)
                } else {
                    UnavailableDevicePushTokenClient()
                },
                stravaCZRepository = UnavailableStravaCZRepository(),
                cache = cache,
                isGradeyCloudConfigured = supabase.isConfigured,
                googleWebClientId = config.googleWebClientId,
            )
        }
    }
}
