# Android Configuration

## App Secrets

Use JDK 21 for local builds. The checked-in Gradle and Android plugin versions were verified with JDK 21.

Do not commit these values. Provide them through local Gradle properties or CI secrets:

- `gradey.supabaseUrl`
- `gradey.supabaseAnonKey`
- `gradey.googleWebClientId`
- `gradey.revenueCatAndroidKey`
- `app/google-services.json`

When Supabase values are blank, the app uses mock repositories with demo school data.

## Google Sign-In

Configure Supabase Auth's Google provider with the Android OAuth client ID for `com.bukovinafilip.gradey`. Register both debug and release SHA-1 fingerprints in Google Cloud, then add the client IDs to the Supabase Google provider settings.

## Firebase Cloud Messaging

The Android app registers FCM tokens with `register-device` using:

```json
{
  "platform": "android",
  "environment": "debug",
  "token": "..."
}
```

Production builds should send `"production"` as the environment if you want separate token tracking.

## Supabase Edge Function Secrets

The shared backend keeps the existing `send-apns` endpoint name for deployment
compatibility and dispatches through APNs or FCM according to the registered
device platform.

Required push secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `PROVIDER_SECRET_KEY`
- `APNS_TOPIC`
- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_PRIVATE_KEY_P8`
- `FCM_PROJECT_ID`
- `FCM_CLIENT_EMAIL`
- `FCM_PRIVATE_KEY`

Set secrets with the Supabase CLI or dashboard. Supabase Edge Functions automatically expose configured secrets through `Deno.env.get(...)`.

## Backend Functions

- `register-device`: accepts `ios`, `macos`, and `android` platforms.
- `poll-new-marks`: records grade history and invokes the push dispatcher.
- `send-apns`: dispatches APNs for Apple platforms and FCM HTTP v1 messages for Android.

## Migration Notes

`202607060001_android_push_platform.sql` widens the
`device_push_tokens.platform` check constraint to include Android. It is applied
automatically for both existing projects and fresh local databases.
