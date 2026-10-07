package com.bukovinafilip.gradey

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory

internal fun configureGradeyFirebase(context: Context) {
    val app = FirebaseApp.initializeApp(context) ?: return
    FirebaseAppCheck.getInstance(app).installAppCheckProviderFactory(
        PlayIntegrityAppCheckProviderFactory.getInstance(),
    )
}
