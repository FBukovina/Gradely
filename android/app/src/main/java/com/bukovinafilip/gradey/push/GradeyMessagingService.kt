package com.bukovinafilip.gradey.push

import com.bukovinafilip.gradey.BuildConfig
import com.bukovinafilip.gradey.GradeyApplication
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class GradeyMessagingService : FirebaseMessagingService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        val graph = (application as? GradeyApplication)?.graph ?: return
        scope.launch {
            val session = graph.gradeyAuthRepository.bootstrapSession() ?: return@launch
            graph.devicePushTokenClient.registerDeviceToken(
                token = token,
                platform = "android",
                environment = if (BuildConfig.DEBUG) "debug" else "production",
                gradeySession = session,
            )
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
    }
}
