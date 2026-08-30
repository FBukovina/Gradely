package com.bukovinafilip.gradey.wear

import android.content.Context
import com.bukovinafilip.gradey.model.GradeyWearSyncContract
import com.bukovinafilip.gradey.model.GradeyWearSyncPayload
import com.bukovinafilip.gradey.network.GradeyJson
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

object PhoneWearSyncPublisher {
    suspend fun publish(context: Context, payload: GradeyWearSyncPayload) {
        val encoded = GradeyJson.encodeToString(GradeyWearSyncPayload.serializer(), payload)
            .encodeToByteArray()
        require(encoded.size <= MAX_DATA_ITEM_BYTES) { "Wear sync payload is too large." }

        val request = PutDataMapRequest.create(GradeyWearSyncContract.DATA_PATH).apply {
            dataMap.putByteArray(GradeyWearSyncContract.PAYLOAD_KEY, encoded)
            dataMap.putLong(GradeyWearSyncContract.GENERATED_AT_KEY, payload.generatedAtEpochMillis)
        }.asPutDataRequest().setUrgent()

        Wearable.getDataClient(context.applicationContext).putDataItem(request).await()
    }

    private const val MAX_DATA_ITEM_BYTES = 100 * 1024
}
