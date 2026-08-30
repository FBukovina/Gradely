package com.bukovinafilip.gradey

import android.app.Application
import com.bukovinafilip.gradey.data.AndroidGradeyConfig
import com.bukovinafilip.gradey.data.AndroidGradeyGraph
import com.bukovinafilip.gradey.data.GradeyCacheOwner
import com.bukovinafilip.gradey.push.GradeyMessagingService
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration

class GradeyApplication : Application(), GradeyCacheOwner {
    lateinit var graph: AndroidGradeyGraph
        private set
    val graphIfReady: AndroidGradeyGraph? get() = if (::graph.isInitialized) graph else null

    override val gradeyCache get() = graph.cache

    override fun onCreate() {
        super.onCreate()

        configureGradeyFirebase(this)
        GradeyMessagingService.createNotificationChannel(this)

        if (BuildConfig.REVENUECAT_ANDROID_KEY.isNotBlank()) {
            Purchases.configure(PurchasesConfiguration.Builder(this, BuildConfig.REVENUECAT_ANDROID_KEY).build())
        }

        graph = AndroidGradeyGraph.create(
            context = this,
            config = AndroidGradeyConfig(
                supabaseUrl = BuildConfig.SUPABASE_URL,
                supabaseAnonKey = BuildConfig.SUPABASE_ANON_KEY,
                googleWebClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID,
                revenueCatAndroidKey = BuildConfig.REVENUECAT_ANDROID_KEY,
            ),
        )
    }
}
