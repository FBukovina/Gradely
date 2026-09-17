package com.bukovinafilip.gradey.wear

import android.content.Context
import com.bukovinafilip.gradey.model.GradeyWearSyncContract
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.tasks.await

class WearDataLayerListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val store = (application as WearGradeyApplication).payloadStore
        // Apply deletions before replacements so a same-batch item from another node can become
        // authoritative even when its generation is older than the removed node's payload.
        for (index in 0 until dataEvents.count) {
            val event = dataEvents[index]
            if (
                event.dataItem.uri.path == GradeyWearSyncContract.DATA_PATH &&
                event.type == DataEvent.TYPE_DELETED
            ) {
                store.deleteSource(event.dataItem.uri.host)
            }
        }
        for (index in 0 until dataEvents.count) {
            val event = dataEvents[index]
            if (
                event.dataItem.uri.path == GradeyWearSyncContract.DATA_PATH &&
                event.type == DataEvent.TYPE_CHANGED
            ) {
                store.updateFrom(event.dataItem)
            }
        }
    }
}

internal enum class WearRefreshResult {
    UPDATED,
    NO_PHONE_PAYLOAD,
}

internal suspend fun refreshWearPayload(context: Context, store: WearPayloadStore): WearRefreshResult {
    val items = Wearable.getDataClient(context.applicationContext).dataItems.await()
    return try {
        val results = mutableListOf<WearPayloadUpdateResult>()
        val matchingSources = buildSet {
            for (index in 0 until items.count) {
                val item = items[index]
                if (item.uri.path == GradeyWearSyncContract.DATA_PATH) item.uri.host?.let(::add)
            }
        }
        store.retainOnlySources(matchingSources)
        for (index in 0 until items.count) {
            val item = items[index]
            if (item.uri.path == GradeyWearSyncContract.DATA_PATH) {
                results += store.updateFrom(item)
            }
        }
        wearRefreshResult(results)
    } finally {
        items.release()
    }
}

internal fun wearRefreshResult(results: Iterable<WearPayloadUpdateResult>): WearRefreshResult =
    if (results.any { it != WearPayloadUpdateResult.INVALID }) {
        WearRefreshResult.UPDATED
    } else {
        WearRefreshResult.NO_PHONE_PAYLOAD
    }

private fun WearPayloadStore.updateFrom(item: DataItem): WearPayloadUpdateResult {
    val encoded = runCatching {
        DataMapItem.fromDataItem(item).dataMap.getByteArray(GradeyWearSyncContract.PAYLOAD_KEY)
    }.getOrNull() ?: return WearPayloadUpdateResult.INVALID
    return update(encoded, item.uri.host)
}
