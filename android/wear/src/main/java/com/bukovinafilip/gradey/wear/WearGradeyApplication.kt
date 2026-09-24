package com.bukovinafilip.gradey.wear

import android.app.Application

class WearGradeyApplication : Application() {
    lateinit var payloadStore: WearPayloadStore
        private set

    override fun onCreate() {
        super.onCreate()
        payloadStore = WearPayloadStore(this)
    }
}
