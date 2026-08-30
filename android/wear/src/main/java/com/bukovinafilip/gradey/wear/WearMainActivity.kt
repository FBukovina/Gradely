package com.bukovinafilip.gradey.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.bukovinafilip.gradey.domain.WearLessonSelector
import com.bukovinafilip.gradey.model.GradeyWearLessonSelection
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.model.NextLessonWidgetTiming
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

class WearMainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val store = (application as WearGradeyApplication).payloadStore
            val payload by store.payload.collectAsState()
            val scope = rememberCoroutineScope()
            var isSyncing by remember { mutableStateOf(false) }

            suspend fun sync() {
                isSyncing = true
                try {
                    refreshWearPayload(applicationContext, store)
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    // The last valid local payload remains usable while disconnected.
                } finally {
                    isSyncing = false
                }
            }

            LaunchedEffect(Unit) { sync() }

            MaterialTheme {
                WearGradeyScreen(
                    payload = payload,
                    isSyncing = isSyncing,
                    onSync = {
                        if (!isSyncing) scope.launch { sync() }
                    },
                )
            }
        }
    }
}

@Composable
private fun WearGradeyScreen(
    payload: GradeyWearSyncPayload?,
    isSyncing: Boolean,
    onSync: () -> Unit,
) {
    val selection = WearLessonSelector.select(payload?.takeIf { it.isSignedIn }?.timetable)
    ScalingLazyColumn {
        item {
            Text("Gradey", style = MaterialTheme.typography.title1)
        }
        payload?.user?.let { user ->
            item {
                Text(
                    listOfNotNull(user.fullName, user.classAbbrev).joinToString(" · "),
                    style = MaterialTheme.typography.caption1,
                )
            }
        }
        item {
            when {
                payload == null -> Text("Open Gradey on your phone to sync")
                !payload.isSignedIn -> Text("Connect Bakaláři in Gradey on your phone")
                selection is GradeyWearLessonSelection.Lesson -> {
                    Text(
                        if (selection.timing == NextLessonWidgetTiming.CURRENT) "Now" else "Next",
                        style = MaterialTheme.typography.caption1,
                    )
                    Text(selection.lesson.detailTitle, style = MaterialTheme.typography.title2)
                    Text(selection.lesson.timeRange ?: "Time unavailable")
                    selection.lesson.room?.let { Text("Room $it") }
                }

                selection == GradeyWearLessonSelection.NoTimetable -> Text("Sync timetable from phone")
                selection == GradeyWearLessonSelection.NoLessons -> Text("Done for today")
                else -> Text("Open phone to refresh")
            }
        }
        item {
            Button(onClick = onSync, enabled = !isSyncing) {
                Text(if (isSyncing) "Syncing…" else "Sync")
            }
        }
    }
}
