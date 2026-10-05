# Gradey Planner account sync

Planner content now belongs to the signed-in Gradey ID. Native devices retain their own Calendar export settings and EventKit identifiers. Imported web items do not automatically request Calendar access or create exports. School providers remain read-only.

The existing unowned `personal-planner.json` stays on its device. After signing in, Planner offers a review sheet listing those items, the target account, and individual selection. Only selected items are copied; the original file is preserved. Per-account JSON under `Application Support/Gradely/PlannerAccounts/<account UUID>.json` atomically stores items, revisions, outstanding mutations, conflicts, and the last cursor. Signing out or changing identity immediately changes the visible local store. Offline writes remain queued and retry on activation, network reconnection, or manual retry.

`POST /functions/v1/planner-sync` accepts `{changes:[{item,baseRevision,mutationId}],cursor}` and returns `{items:[{item,revision}],conflicts:[{itemId,remote}],cursor,acceptedMutationIds}`. Dates use ISO 8601. Requests contain at most 100 distinct item IDs and 512 KB; titles and notes are limited to 500 and 20,000 UTF-16 code units. The explicit content DTO excludes all Calendar fields. The gateway authenticates with `auth.getUser`, and derives the owner exclusively from that identity.

The database function is service-role-only, uses a transactionally locked global revision counter to avoid commit-order cursor gaps, checks base revisions, and stores idempotent mutation IDs. Authenticated database clients can only read their own rows and cannot bypass the mutation protocol. Deletes retain tombstones. A conflicting local edit stays visible until the user chooses a version. Retaining an edit of an item deleted remotely creates a new UUID.

## Rollout

1. Apply the additive Planner migration and deploy only `planner-sync`; do not redeploy unrelated functions.
2. Enable email signup and configure the OTP email template (the checked-in template contains `{{ .Token }}`). Configure production SMTP and delivery limits; the native/web code alone cannot change live Auth settings. Preserve Apple sign-in and its existing user IDs. Web Apple sign-in additionally needs a registered Services ID and approved HTTPS redirects.
3. Deploy the web client and native release against the same Supabase and RevenueCat identity. Verify one existing Apple account and one email account on both platforms. Do not merge accounts just because display names match.
4. Verify edit, completion, delete, offline retry, ambiguous-response retry, simultaneous conflict resolution, account switching during sync, selected legacy import, and Calendar export on a real native device. No native release, live migration, email delivery, or deployed sync is implied by source tests.

## Verification

`GradelyTests/PlannerCloudTests.swift` covers per-account queues, durable restore, import review, account-switch races, Calendar privacy, tombstones, and conflict copies. `GradeyAuthClientTests.swift` covers the email request/verification contract. The cloud tests and auth tests can be compiled in isolation with app shell/Calendar stubs when full Xcode dependency resolution is unavailable; that does not validate SwiftUI rendering or EventKit delivery.

Run `./scripts/test-planner-cloud.py` on macOS with Xcode command-line tools to compile current production Planner/auth sources and execute the focused suites in a temporary package. The checked-in harness stubs only app localization, surrounding timetable types, and Calendar authorization; it extracts the current account and Keychain declarations from production source. Optional `GRADEY_PLANNER_TEST_SCRATCH` keeps a build cache at a chosen path. The tests also cover stale editor drafts, competing local-window edits, bounded batches, and the 25-hour Prague daylight-saving date.

Run `deno test supabase/functions/_shared/planner-sync_test.ts` and `deno check supabase/functions/planner-sync/index.ts`. Run `./scripts/test-web-migrations.py` with local PostgreSQL binaries (or `GRADEY_TEST_PG_BINDIR`) for an automatically cleaned, Unix-socket-only database. It applies the original platform schema and the three additive Planner, web notification, and session-vault migrations, then runs the rolled-back SQL fixtures. The notification fixtures include lesson-only reminders. This focused check does not replace a full Supabase reset of the complete migration chain. Never run the fixture SQL scripts against production.
