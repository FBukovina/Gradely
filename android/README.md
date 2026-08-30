# Gradey Android

Native Kotlin Android port of Gradey.

This directory is the Android workspace inside the Gradely monorepo. Open this
directory, rather than the repository root, in Android Studio.

This repository is scaffolded as a full Android ecosystem:

- `:app` phone app with Jetpack Compose and Material 3
- `:wear` Wear OS Compose app
- `:glance-widgets` Android home-screen widgets
- shared model, domain, network, data, and UI modules
- the shared root `../supabase/` backend with APNs and FCM push support

The default local build runs with demo data when Supabase credentials are not supplied.

## Local Setup

1. Open the repo in Android Studio.
2. Use JDK 21 for local Gradle builds. Android Studio can manage this through Gradle JDK settings.
3. Keep `local.properties` local to your machine.
4. Optional live configuration goes in `~/.gradle/gradle.properties` or a local untracked Gradle properties file:

```properties
gradey.supabaseUrl=https://YOUR_PROJECT.supabase.co
gradey.supabaseAnonKey=YOUR_SUPABASE_ANON_KEY
gradey.googleWebClientId=YOUR_GOOGLE_WEB_CLIENT_ID
gradey.revenueCatAndroidKey=YOUR_REVENUECAT_ANDROID_KEY
```

5. Add `app/google-services.json` locally for Firebase Messaging.
6. Build with:

```sh
./gradlew :app:assembleDebug :wear:assembleDebug test
```

## Backend

The canonical Supabase backend lives at `../supabase/`. Its existing
`send-apns` endpoint is a backward-compatible cross-platform dispatcher that
uses APNs for Apple devices and FCM HTTP v1 for Android devices.

See [docs/android-configuration.md](docs/android-configuration.md).
