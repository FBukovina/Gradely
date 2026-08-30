package com.bukovinafilip.gradey.push

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.bukovinafilip.gradey.BuildConfig
import com.bukovinafilip.gradey.data.AndroidGradeyGraph
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object GradeyPushRegistration {
    private val registrationMutex = Mutex()

    suspend fun refreshIfEligible(context: Context, graph: AndroidGradeyGraph): Boolean {
        if (!canRegister(context, graph)) return false
        val token = try {
            FirebaseMessaging.getInstance().token.await()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            return false
        }
        return registerKnownTokenIfEligible(context, graph, token)
    }

    suspend fun registerKnownTokenIfEligible(
        context: Context,
        graph: AndroidGradeyGraph,
        token: String,
    ): Boolean {
        if (token.isBlank() || !canRegister(context, graph)) return false
        return try {
            registrationMutex.withLock {
                val session = graph.gradeyAuthRepository.validSession()
                val environment = if (BuildConfig.DEBUG) "debug" else "production"
                if (!graph.pushRegistrationStore.needsRegistration(token, session.account.id, environment)) {
                    return@withLock true
                }
                graph.devicePushTokenClient.registerDeviceToken(
                    token = token,
                    platform = "android",
                    environment = environment,
                    gradeySession = session,
                )
                graph.pushRegistrationStore.markRegistered(token, session.account.id, environment)
                true
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Keep the identity uncommitted so startup or a later token callback retries.
            false
        }
    }

    private fun canRegister(context: Context, graph: AndroidGradeyGraph): Boolean =
        graph.isGradeyCloudConfigured &&
            FirebaseApp.getApps(context).isNotEmpty() &&
            (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
                )
}
