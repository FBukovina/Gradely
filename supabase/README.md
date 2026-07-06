# Gradey 2.0 Supabase Backend

This folder contains the Gradey ID platform backend:

- Auth uses Supabase Auth with Sign in with Apple.
- Linked provider sessions are stored as encrypted payloads through `store_provider_secret`; school and canteen passwords are intentionally not accepted by the app payloads.
- `poll-new-marks` baselines marks on first link, then inserts new mark events only for unseen fingerprints.
- `send-apns` delivers APNs alert pushes and invalidates rejected device tokens.

## Remote project

- Project ref: `<your-project-ref>`
- Project URL: `https://<your-project-ref>.supabase.co`
- Region: `eu-central-1`
- App redirect URL: `gradey://auth`

As of 2026-07-01, the remote project is active, migrations have been applied, all Edge Functions are deployed, Apple auth is enabled, email signups are disabled, APNs secrets are configured, and the `gradey-poll-new-marks` cron job runs every five minutes through `pg_cron` + `pg_net`.

Required project secrets:

```sh
supabase secrets set PROVIDER_SECRET_KEY="at-least-32-random-characters"
supabase secrets set CRON_SECRET="random-cron-secret"
supabase secrets set APNS_TEAM_ID="..."
supabase secrets set APNS_KEY_ID="..."
supabase secrets set APNS_TOPIC="com.bukovinafilip.BakalariMarks"
supabase secrets set APNS_PRIVATE_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"
```

Schedule polling with Supabase scheduled functions:

```sh
supabase functions deploy poll-new-marks --no-verify-jwt
supabase functions deploy send-apns --no-verify-jwt
```

Run `poll-new-marks` every few minutes and pass `x-cron-secret: $CRON_SECRET`; the function chooses the next per-account poll time using the 15-minute daytime / hourly overnight rule.

The remote schedule is managed by `migrations/202607010001_gradey_scheduled_polling.sql`. It stores the project URL and cron secret in Supabase Vault, then calls `/functions/v1/poll-new-marks` every five minutes.

## Apple auth maintenance

Apple auth settings live in `config.toml` and are pushed with the Supabase CLI. The Apple client secret is a signed JWT generated from the Apple `.p8` key and expires after about six months, so rotate it before expiry and run `supabase config push --project-ref <your-project-ref> --yes` with `APPLE_CLIENT_SECRET` set in the shell environment.

Do not commit Apple private keys, client secret JWTs, Supabase service role keys, or cron secrets.

## Passkeys

Do not enable passkeys until Gradey has a stable HTTPS domain and Associated Domains entry for the passkey Relying Party ID. Changing the Relying Party ID later would strand already-created passkeys.
