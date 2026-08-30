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
        dataEvents.forEach { event ->
            if (event.dataItem.uri.path != GradeyWearSyncContract.DATA_PATH) return@forEach
            when (event.type) {
                DataEvent.TYPE_CHANGED -> store.updateFrom(event.dataItem)
                DataEvent.TYPE_DELETED -> store.clear()
            }
        }
    }
}

suspend fun refreshWearPayload(context: Context, store: WearPayloadStore): Boolean {
    val items = Wearable.getDataClient(context.applicationContext).dataItems.await()
    return try {
        var updated = false
        for (index in 0 until items.count) {
            val item = items[index]
            if (item.uri.path == GradeyWearSyncContract.DATA_PATH) {
                updated = store.updateFrom(item) || updated
            }
        }
        updated
    } finally {
        items.release()
    }
}

private fun WearPayloadStore.updateFrom(item: DataItem): Boolean {
    val encoded = DataMapItem.fromDataItem(item).dataMap
        .getByteArray(GradeyWearSyncContract.PAYLOAD_KEY)
        ?: return false
    return update(encoded)
}
