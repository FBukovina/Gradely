# Push notification rollout — 29 September 2026

Production project: `ieonvnfzkbyybbkfxupq`.

## What production actually showed

The live poller was version 6, with access-token-only Bakaláři requests and no
refresh path. It paused accounts after any three failures, including temporary
school HTTP 500 errors. Recent completed poll responses contained
`bakalari_status_500`; token expiry alone was not established as the cause.

At the pre-deployment check, 30 school links required action and 5 were active.
None had a recorded successful baseline poll. No notification events had been
created in the previous seven days. Both cron jobs were active, but successful
cron SQL execution only proved that an HTTP request was queued. `pg_net` recorded
five-second HTTP timeouts, including DNS timeouts. A verification invocation with
a longer timeout also stalled for 120 seconds.

## Deployed changes

| Component | Version / migration | Verification |
| --- | --- | --- |
| `activate-school-account` | 2 | Source and dependencies match checkout; JWT enabled |
| `link-school-account` | 8 | Source and dependencies match checkout; JWT enabled |
| `relink-school-account` | 3 | Source and dependencies match checkout; JWT enabled |
| `poll-new-marks` | 8 | Dedicated token renewal, account leases, bounded provider requests |
| Atomic mark recording | `20260929124428_atomic_mark_notifications` | Applied and tested with rolled-back synthetic fixtures |
| Poll cron timeout | `20260929124742_polling_cron_timeout` | 120 seconds; existing five-minute schedule and active state preserved |

The poller atomically claims a due account for ten minutes. The claim checks the
secret ID and returns current account state, so a stale account listing cannot
overwrite a reconnect. Failure updates also check the session and active status.
Temporary provider failures back off without pausing the account. Provider HTTP
requests share a 30-second deadline per account; the worker stops starting new
accounts after its 60-second batch budget. Unstarted accounts remain due.

`record_polled_marks` writes fingerprints, notification events, and baseline
completion in one database transaction. Errors cannot leave marks permanently
seen without their events. Retrying a committed result does not duplicate events.
The RPC is invoker-security and executable only by `service_role`. Results from a
replaced school session are skipped. Existing fingerprints are preserved;
historical marks are not replayed and an initial baseline remains silent.

The activation function no longer returns the poller's refresh token. Link and
relink require the supported tokens-only client header and a dedicated polling
session. Older clients must update before linking or reconnecting. No school
passwords are accepted by these functions. The existing database sanitizer was
verified to preserve `pollingSessionEstablishedAt`.

`send-apns` was left at its existing production version 8. No test push or school
data was fabricated. The foreground banner/sound fix in
`Gradely/Support/SchoolNavigation.swift` is still a local app change and requires
an app build/release to reach installed clients.

## Validation and remaining device check

- All 46 shared Deno tests passed; all four deployed functions type-checked.
- Real local PostgreSQL checks passed for baseline silence, per-mark events,
  duplicate retries, event-failure rollback and recovery, stale sessions, and
  role permissions. The same SQL fixture passed against production and rolled
  back all its synthetic rows.
- Concurrent local database sessions produced one lease winner and one durable
  event when both attempted the same work.
- The deployed function bundles were downloaded and compared to the submitted
  source. Unauthenticated POST requests to all four functions returned HTTP 401.
- The 12:50 UTC scheduled poll completed with HTTP 200 and zero due accounts;
  this proves invocation, not a successful school fetch. At 12:51 UTC, the same
  30 action-required and 5 active accounts still had no successful baseline.
  No synthetic test users remained in production. The user could not check the
  app during this rollout, so session recovery and physical delivery are pending.
- Security-advisor findings were unchanged: two intentionally closed RLS tables,
  existing Auth leaked-password protection and MFA warnings. See the existing
  [RLS](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
  [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection),
  and [MFA](https://supabase.com/docs/guides/auth/auth-mfa) guidance.

Open an updated Gradey client and reconnect if requested. Verify a real account
completes its baseline and continues polling beyond its access-token lifetime,
then verify a genuinely new mark reaches a physical device. Deployment and
database tests alone do not prove those outcomes. Paused accounts were not
blindly reactivated, and no application binary was uploaded by this rollout.

## Follow-up — 4 October 2026: the HTTP 500s were ours

The `bakalari_status_500` responses above were not temporary school failures.
Deno's `fetch` sends `Accept-Language: *` by default, and Bakaláři's IIS servers
answer any request carrying it with `500 {"Message":"An error has occurred."}`.
`curl` with the same header reproduces it; with `Accept-Language: cs-CZ` the same
servers return the expected 401 to an invalid token. Probes used only a bogus
bearer token against three linked schools. The app was unaffected because iOS
sends a real language.

Consequently, before this fix no account had ever completed a poll: all 35
school links had `last_polled_at = NULL`, one active account had 64 consecutive
failures, and no new-mark events existed. Cron execution and `pg_net` delivery
were healthy (every call in the 6-hour response window returned HTTP 200).

`poll-new-marks` version 9 sets `Accept-Language: cs-CZ` on both Bakaláři
requests (marks and token refresh). The deployed bundle was downloaded and
matched the checkout; `verify_jwt` remains false for the cron caller. At
17:20 UTC the first-ever successful poll baselined an account: 22 marks across
11 subjects, 11 grade-history rows, zero notification events (baselines are
silent), failure count reset, next poll 15 minutes later.

By 17:50 UTC three accounts had baselined with no poll errors, and the first
had completed a follow-up (non-baseline) poll. Their polling tokens were last
uploaded 104–125 hours earlier, so every one of these polls first renewed an
expired access token through the poller's own refresh token: the refresh path
works, and an unredeemed Bakaláři refresh token was still accepted after five
days. The remaining active accounts baseline as their backoff windows expire.

Still to verify: a genuinely new mark reaching a physical device. The 17
`action_required` accounts recover when their owners next open Gradey.
