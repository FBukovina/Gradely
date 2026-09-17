# Gradey 2.0 Supabase Backend

This folder contains the Gradey ID platform backend:

- Auth uses Supabase Auth with Sign in with Apple.
- Linked provider sessions are stored as encrypted payloads through `store_provider_secret`; school and canteen passwords are intentionally not accepted by the app payloads.
- `poll-new-marks` baselines marks on first link, then inserts new mark events only for unseen fingerprints.
- `send-apns` is the backward-compatible cross-platform push endpoint. It atomically claims due events, enforces global and per-school switches, defers quiet-hours events, summarizes one complete quiet-window group, sends through APNs or FCM, and tracks acceptance, retry, or suppression independently for every target device.
- Authenticated settings functions return canonical account state, update preferences, reconnect an owned school account in place, export user-owned data, and delete the Gradey ID account.

## Remote project

- Project ref: `<your-project-ref>`
- Project URL: `https://<your-project-ref>.supabase.co`
- Region: `eu-central-1`
- App redirect URL: `gradey://auth`

As of 2026-07-19, the remote project is active, migrations through `20260718225228` have been applied, all Edge Functions are deployed, Apple auth is enabled, email signups are disabled, APNs secrets are configured, `gradey-poll-new-marks` runs every five minutes, and `gradey-send-apns` runs every minute through `pg_cron` + `pg_net`.

Required project secrets:

```sh
supabase secrets set PROVIDER_SECRET_KEY="at-least-32-random-characters"
supabase secrets set CRON_SECRET="random-cron-secret"
supabase secrets set APNS_TEAM_ID="..."
supabase secrets set APNS_KEY_ID="..."
supabase secrets set APNS_TOPIC="com.bukovinafilip.BakalariMarks"
supabase secrets set APNS_PRIVATE_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"
supabase secrets set FCM_PROJECT_ID="..."
supabase secrets set FCM_CLIENT_EMAIL="..."
supabase secrets set FCM_PRIVATE_KEY="$(cat firebase-service-account-private-key.pem)"
```

Schedule polling with Supabase scheduled functions:

```sh
supabase functions deploy poll-new-marks --no-verify-jwt
supabase functions deploy send-apns --no-verify-jwt
```

Run `poll-new-marks` every few minutes and pass `x-cron-secret: $CRON_SECRET`; the function chooses the next per-account poll time using the 15-minute daytime / hourly overnight rule.

The polling schedule is managed by `migrations/202607010001_gradey_scheduled_polling.sql`. The settings/notification migration also calls `/functions/v1/send-apns` every minute so deferred and retryable events are recovered. Both schedules reuse the project URL and cron secret stored in Supabase Vault.

The nested `poll-new-marks` → `send-apns` request is latency-only and best effort; the one-minute Cron dispatcher is the correctness and recovery path, including when the platform rate-limits nested Edge Function calls.

Before deploying the client, apply migrations and deploy the backward-compatible functions. The notification migration suppresses pre-migration undelivered events so an old-notification burst cannot occur. Verify `cron.job_run_details` for both `gradey-poll-new-marks` and `gradey-send-apns`, and inspect dispatcher logs for claimed, sent, rescheduled, suppressed, retried, and invalidated-token counts.

Push delivery is intentionally at-least-once. Each event/device target persists a stable delivery identity; quiet summaries derive a stable request and collapse identity from the persisted quiet-window key and device ID. If a worker stops after a provider accepts a request but before the database commit, a successful target remains independently terminal once recorded and is never retried merely because a different device failed.

## Apple auth maintenance

Apple auth settings live in `config.toml` and are pushed with the Supabase CLI. The Apple client secret is a signed JWT generated from the Apple `.p8` key and expires after about six months, so rotate it before expiry and run `supabase config push --project-ref <your-project-ref> --yes` with `APPLE_CLIENT_SECRET` set in the shell environment.

Do not commit Apple private keys, client secret JWTs, Supabase service role keys, or cron secrets.

## Passkeys

Do not enable passkeys until Gradey has a stable HTTPS domain and Associated Domains entry for the passkey Relying Party ID. Changing the Relying Party ID later would strand already-created passkeys.
