# Gradey Android feature parity

This is the authoritative implementation and verification checklist for the Android app. The current iOS app is the behavior, feature, copy, navigation, and visual reference unless a row is explicitly marked `DIFFERENT` or `N/A`.

Last source audit: 2026-08-30 on `codex/android-monorepo`.

## Status rules

- `[x]` means the Android behavior was implemented and independently verified by a relevant test or manual end-to-end check.
- `[ ]` means missing, partial, placeholder-backed, demo-backed, or not yet verified.
- `DIFFERENT` documents an intentional Android-native equivalent.
- `N/A` documents an iOS feature that intentionally has no Android counterpart.
- A compiling screen is not sufficient for `[x]`.

## Audited iOS reference

- [x] App shell and lifecycle audited: `GradelyApp`, `ContentView`, `AppEnvironment`, app phases, tab composition, deep links, onboarding resume, account-change reset, and watch/push startup.
- [x] Bakaláři stack audited: models, API client, repository, URL normalization, secure sessions, scoped marks/absence/timetable caches, refresh serialization, rejected-token handling, optional endpoints, absence fallback, timetable mapping, and what-if requests.
- [x] Main product areas audited: Today, Subjects, Subject detail, Absence, Timetable, Strava.cz meals, Gradey AI, settings/account hub, support, credits, debug panel, language picker, and age gate.
- [x] Gradey cloud stack audited: Gradey ID, guest mode, linked accounts, account activation/reconnect, grade history, mark fingerprints, push registration, notification preferences, export, and account deletion.
- [x] Platform surfaces audited: next-lesson widget, Apple Watch app, complications, direct watch Bakaláři refresh, phone/watch sync, and AI relay.
- [x] Design and content audited: shared design system, Hugeicons Stroke Rounded mapping, Space Grotesk display typography, component states, 760 primary localization entries, 105 Chronically Online entries, Czech and English variants, accessibility identifiers, and adaptive layouts.
- [x] Apple-only integrations classified below rather than copied blindly to Android.

## Repository and build baseline

- [x] Android lives under `android/` in the existing Gradey repository without moving or rewriting the iOS project.
- [x] Android app, Wear app, shared modules, and root Supabase backend build from the monorepo layout at commit `82c563c`.
- [x] The imported baseline passed `:app:assembleDebug`, `:wear:assembleDebug`, and JVM tests before the local Android Studio Gradle upgrades.
- [x] Re-run the complete build and test suite with the current local AGP 9.3.2 / Gradle 9.5 / KSP 2.3.6 upgrades.
- [x] Add Android CI that builds, tests, and checks resources/navigation from the monorepo path.
- [x] Keep the branch and pull request reviewable with no unrelated iOS changes.

## Supported provider scope

- [x] Remove `SchoolProvider.EDU_PAGE`, EduPage models, URL normalization, client interfaces, parser, repository branches, login UI, and unsupported-client wiring from Android.
- [x] Migrate or safely reject any locally stored Android EduPage session without crashing startup.
- [x] N/A — EduPage login, two-factor approval, child selection, child switching, and EduPage timetable parsing will not be ported to Android.
- [x] Make all Android school/account copy consistently say Bakaláři rather than implying multiple school providers.
- [x] Preserve Bakaláři attribution and relevant legal/source acknowledgement.

Bakaláři attribution verification (2026-08-30): Android Account now presents the same explicit notice as iOS that Gradey uses an unofficial integration and is neither a Bakaláři product nor affiliated with or endorsed by Bakaláři software. The title and full notice are packaged for standard English, standard Czech, English Chronically Online, and Czech Chronically Online configurations; Android resource merging and lint verify every locale contains the required keys.

## Startup, age gate, onboarding, and language

- [x] Show a branded checking/splash state while local Gradey ID and school sessions are restored.
- [x] Reproduce the current iOS age-attestation gate, persisted choice, under-16 parent/guardian confirmation (including under 13), privacy link, and Settings summary.
- [x] Reproduce current new-user onboarding: welcome/benefits, language, Gradey ID or local guest choice, school discovery/credentials, notification permission, readiness summary, and resumable progress.
- [x] Reproduce upgrade onboarding for existing school sessions, including local connection migration and cloud-link warning/retry states.
- [x] Persist onboarding progress and completion without restart loops.
- [x] Implement system language, English, Czech, and Chronically Online variants using Android resources.
- [x] Apply locale changes throughout the running app and persist them.
- [ ] Remove hard-coded English strings from production Compose screens.

Age-gate verification (2026-08-30): Android uses the same three self-attestation categories and persisted `gradey.ageAttestation.v1` values as current iOS. Until a valid value exists, the age chooser precedes auth/school bootstrap. The 13–15 and under-13 paths both require an affirmative parent/guardian checkbox, matching the current EU/GDPR iOS implementation; the 16+ path confirms directly. The gate links to Gradey's privacy policy and Account shows the saved age summary. Model and store tests cover every cross-platform storage value, unknown-value fail-closed behavior, parental-consent classification, persistence, and restoration.

Onboarding verification (2026-08-30): restoration now uses a dedicated Gradey splash instead of a disabled login form. Android persists the current iOS `newUser`/`upgrade` journey and welcome/account/school/notifications/ready/support step values under `onboarding.progress.v2`, records completion separately, repairs the legacy step-only/meals format, clears corrupt progress, and does not recreate progress after completion. Route-policy tests rebuild interrupted flows from durable guest, Gradey ID, and Bakaláři state. The implemented new-user flow includes the localized iOS welcome and benefits, an in-flow language picker, the real Google/local choice, live school discovery and credentials, Android 13+ notification permission, a readiness summary, and resumable progress. The upgrade journey preserves the existing device session, attempts its cloud migration, displays a truthful non-destructive warning when linking fails, and offers an explicit retry before finishing.

Language verification (2026-08-30): Android uses the same persisted `settings.appLanguage` values and locale tags as Swift: `system`, `english`, `englishChronicallyOnline`, `czech`, and `czechChronicallyOnline`, with `en-CO` and `cs-US` selecting the alternate voice. The picker is available during onboarding and in Account, preserves the selected base language when toggling the voice, and applies a localized Compose context immediately without restarting or recreating authenticated state. JVM tests cover every storage value, locale tag, unknown-value fallback, persistence, explicit-language toggling, and system-language resolution. The assembled app contains default, `cs`, `en-rCO`, and `cs-rUS` resource configurations. The hard-coded-English row remains open while the rest of the production screens are migrated incrementally.

## Gradey ID and guest mode

- [x] Replace the hard-coded `demo-google-id-token` path with a real Credential Manager Google sign-in flow.
- [x] Restore and refresh Gradey auth sessions from encrypted storage with serialized refresh and explicit expired-session handling.
- [x] Implement Gradey ID profile refresh and full-name editing/validation.
- [x] Implement “continue without account” guest mode and preserve local Bakaláři use without requiring Supabase configuration.
- [x] Make unavailable cloud configuration an honest Gradey ID capability state, never a switch to mock repositories.
- [x] Implement guest-to-Gradey-ID upgrade without losing the local school session.
- [x] Implement complete sign-out and school-only sign-out semantics matching iOS.
- [x] DIFFERENT — Android uses Google sign-in; Sign in with Apple UI is not copied from iOS.

Verification evidence (2026-08-30): Android uses Credential Manager's Google ID-token credential and exchanges it with Supabase; no demo token path remains. Gradey ID sessions restore from Keystore-backed encrypted preferences with corrupt-record cleanup, refresh within a 60-second expiry window, serialize concurrent refresh/sign-out mutations, retain rotated or omitted refresh-token fields safely, and clear only on explicit 400/401 refresh rejection or missing refresh credentials. MockWebServer tests cover one-request refresh fan-in, rejected refreshes, transient 5xx and transport failures, profile GET/PUT authorization, 1...80-character trimmed name validation, credential exchange, and a delayed-refresh/sign-out race. Startup keeps the restored account and Bakaláři session through temporary cloud/profile outages, while Account exposes canonical profile refresh and validated name editing. Builds without cloud configuration display a local-only capability state and use unavailable repositories rather than mocks.

Guest verification (2026-08-30): the sign-in gate offers an explicit local-only choice backed by the persisted `gradey.guestMode.enabled.v1` preference. Startup-policy tests cover configured signed-out, persisted guest, unconfigured local-only, needs-school, and fully signed-in combinations. Entering guest mode clears any Gradey ID session and cloud-linked snapshot but preserves the independent Bakaláři session; Account can return to Google sign-in, and a successful upgrade reloads the existing school immediately. Guest/local-only sign-out disconnects only Bakaláři and meals while retaining the guest choice, whereas Gradey ID sign-out clears cloud identity, linked accounts, school/meals sessions, Credential Manager state, widget data, and Wear data.

## School discovery and Bakaláři login

- [x] Port municipality and school directory discovery from `sluzby.bakalari.cz`, including bounded concurrency, retry, timeout, deduplication, sorting, and healthy-cache replacement rules.
- [x] Show cached school search immediately and refresh it only when stale or on retry.
- [x] Implement diacritic-insensitive searchable school selection, no-results, loading, and retained partial-cache states.
- [x] Verify the visible initial lookup-error and retry interaction end to end with the directory unavailable.
- [x] Retain a clearly explained manual school URL path.
- [x] Bakaláři base URL normalization and validation logic has JVM coverage for scheme, host, path, and insecure/invalid inputs.
- [x] Match iOS credential validation, password visibility, loading, cancellation, retry, readable server error, and demo-account behavior.
- [x] Never prefill production login fields with demo credentials.
- [x] Keep the intentional App Review demo account isolated to the documented demo host and exact credentials.
- [ ] Verify login against representative real Bakaláři server versions.

Verification evidence (2026-08-30): Android decoded the live Bakaláři municipality/town responses, completed healthy coverage under the iOS deadline, cached 2,777 unique schools, restored that cache without a loading flash after a cold restart, found `Adršpach` from the unaccented query `adrspach`, filled the selected URL, retained the manual URL path, showed the offline lookup error, and completed a live retry after connectivity returned.

Credential verification (2026-08-30): the login form now validates the school URL through the shared HTTPS normalizer and gives field-specific username/password guidance without trimming or changing the password. It provides appropriate URL/text/password keyboards, a working password visibility control, progress state, an explicit cancel action wired to coroutine and OkHttp cancellation, editable retry after safe server errors, and stale-error clearing when input changes. The App Review demo remains opt-in rather than prefilled; its exact `demo.gradely.app` / `apple-review` / `GradelyDemo2026!` tuple uses the fixture client, a wrong tuple on that host is rejected locally without any live request, and the same credentials on another host still use the real Bakaláři client. JVM tests cover field validation, insecure/invalid URLs, exact host matching (including a lookalike-host rejection), correct/wrong demo routing, and live-host isolation; existing MockWebServer tests cover encoded credentials, cancellation, structured errors, HTML sanitization, timeout, offline, and authentication failures.

## Bakaláři session and account lifecycle

- [x] Store Bakaláři tokens and any fallback credentials with Android Keystore-backed encrypted storage and an explicit migration/version strategy.
- [x] Restore the current school session at startup without network access.
- [x] Refresh before expiry and serialize simultaneous refresh requests.
- [x] Retry a request only for access-token rejection, not for every network/decoding/server error.
- [x] Fall back from a rejected refresh token to credential login only under the same conditions as iOS.
- [x] Clear an unrecoverable expired session and route to reconnect without discarding unrelated local preferences.
- [x] Scope caches by provider/server/user/linked-account identity so accounts cannot see each other’s data.
- [x] Implement local linked-account persistence, cloud account linking, activation, reconnect, unlink, status, and per-account notification setting with real repositories.
- [x] Implement safe school account switching and reset all visible feature state after activation.
- [x] Preserve the local school session when a Gradey cloud call is temporarily unavailable.

Verification evidence (2026-08-30): school tokens and fallback credentials remain in Android Keystore-backed encrypted preferences. The session store now writes a versioned `v2` envelope, migrates the prior raw `v1` Bakaláři record without signing the user out, rejects unknown future versions safely, clears both keys on explicit logout, and restores the saved session without making a Bakaláři request.

Linked-account verification (2026-08-30): Android now calls the same `account-settings`, `link-school-account`, `activate-school-account`, `relink-school-account`, `update-linked-account-preferences`, and `unlink-account` Supabase functions as Swift, with a cache-first encrypted local snapshot and the same request field names and Bakaláři credential payload. Failed refreshes and mutations retain the prior snapshot; server errors are bounded and raw HTML is not surfaced. Android decodes and preserves Strava.cz and legacy EduPage records created on iOS but only offers activation/reconnect for supported Bakaláři accounts. Startup restores the backend-preferred active school, or an unambiguous single active school, and never guesses among multiple accounts or activates an action-required/unsupported record. Switching clears all visible feature state before loading the target account's scoped caches. Activation keeps the device's existing token family for the same linked account and mints a separate Bakaláři token family from encrypted credentials for another account, avoiding refresh-token races with Gradey's cloud poller. Tests cover exact requests, settings decode, provider compatibility, activation, reconnect, preference updates, unlink cache safety, session association/detachment, and restoration selection.

## Bakaláři HTTP, parsing, and compatibility

- [x] Introduce typed Android errors for invalid response, HTTP status/body, decoding, authentication, timeout, cancellation, and offline failure.
- [x] Parse readable Bakaláři login error bodies without exposing raw HTML or secrets.
- [x] Verify percent-encoded login/refresh forms and JSON what-if bodies against iOS fixtures.
- [x] Add request/connect/read timeouts and cancellation-aware OkHttp coroutine execution.
- [x] Treat user and absence endpoints as optional where iOS does, without failing marks/dashboard.
- [x] Preserve previous content when an optional endpoint or background refresh fails.
- [x] Harden JSON decoding for nullable, missing, malformed, numeric/string, and server-version differences found in real Bakaláři responses.
- [x] Verify dates and timetable week boundaries in Europe/Prague, including daylight-saving changes and device timezones.
- [x] Add fixture tests for empty data, partial data, malformed data, 401/403, 404 optional endpoints, 5xx, timeout, offline, and refresh rejection.
- [x] Confirm no credentials, tokens, or sensitive response bodies are logged.

Verification evidence (2026-08-30): repository tests cover optional user/absence 404s, cached user and per-subject absence retention, cancellation propagation, rejected refresh plus rejected credential login, missing fallback credentials, and transient offline re-login failure. Unrecoverable authentication clears only the stored school session, retains scoped cache entries, and is handled by the app shell as a reconnect transition with visible feature state reset. Network fixtures also cover missing collections/mark fields, comma-decimal and malformed weights, the real object-shaped Bakaláři class, legacy string classes, preferred organization names, numeric timetable hour IDs, missing timetable display fields, and unknown response fields.

Date verification (2026-08-30): app startup, cache lookup, refresh, repository mapping, and timetable fallback now derive the school day in `Europe/Prague`, independent of the device timezone. JVM tests pin instants across both 2026 Prague DST transitions, Sunday-to-Monday week boundaries, duplicate atoms, missing dates/hours/references, raw whitespace-sensitive IDs, sorting, and change mapping.

Error verification (2026-08-30): Bakaláři transport now distinguishes safe HTTP, authentication, invalid/empty response, decoding, timeout, offline, and other I/O failures while propagating coroutine cancellation unchanged. MockWebServer and repository tests cover empty and partial payloads, malformed success bodies, 401/403, optional 404s, 5xx HTML, socket timeout, offline DNS failure, generic transport failure, cancellation, and refresh rejection. Raw HTTP bodies are discarded from outward exception causes, user messages are bounded/sanitized, and a production-source scan found no request/response logger, credential logging, token logging, `println`, or stack-trace printing.

## Cache and offline behavior

- [ ] Load scoped cached marks, absence, timetable weeks, meals, linked accounts, and grade history before refreshing.
- [ ] Retain cached/loaded content on background refresh failure and expose a non-destructive stale/error indication.
- [ ] Show full error/retry only when there is no usable content.
- [x] Preserve multiple timetable weeks and their cache timestamps.
- [x] Make force refresh refresh data rather than deleting usable cache before a network request succeeds.
- [ ] Implement targeted cache clearing for current school, all school data, account reset, and sign-out.
- [x] Remove all refresh fallbacks to `DemoData` from production state.
- [ ] Verify offline cold start, offline warm start, reconnect, expired offline session, and corrupt-cache recovery.

Cache verification (2026-08-30): Today and Marks now render from a cached/loaded dashboard even when the optional absence request is unavailable, using any per-subject absence already embedded in the dashboard. A failed background refresh leaves existing content on-screen and displays a compact non-destructive warning; first-load errors retain the full retry surface. Repository tests prove forced dashboard and timetable failures do not delete their cached values, two timetable weeks and timestamps coexist under separate keys, and school logout clears only the active school scope while preserving an unrelated scope. Timetable week navigation now renders the requested scoped cache before refreshing, clears a previously displayed different week when the requested week has no usable cache, replaces cached content only after success, and retains it after refresh failure. The warning overlay is gated by usable content for the selected feature, so an unavailable feature receives its full retry state rather than a misleading background warning caused by another tab's cache. Cache-first loader tests cover cache/fresh ordering, retained content, missing and corrupt cache recovery, and cancellation.

## Today

- [ ] Implement initial/loading/loaded/empty/refreshing/background-error states without demo fixtures.
- [ ] Match the iOS overall-average hero, student identity, subject/mark counts, and refresh behavior.
- [ ] Implement linked school account picker, activation progress, action-required banner, reconnect sheet, and automatic recovery rules.
- [ ] Implement current/next lesson summary with before-school, between-lessons, in-lesson, after-school, weekend, holiday, and timetable-change states.
- [ ] Implement new-mark feed using cloud history with Bakaláři `IsNew` fallback.
- [ ] Implement grade trend summary and full 30/90-day/school-year trend navigation.
- [ ] Implement top absence risks, no-threshold messaging, and navigation to Absence.
- [ ] Implement today’s ordered meal, not-connected/no-meal states, and optional navigation to Meals.
- [ ] Preserve independent partial content when timetable, absence, meals, history, or linked-account refresh fails.
- [ ] Wire the real Gradey AI entry rather than routing the sparkle button to Meals.

## Subjects and marks

- [ ] Implement cache-first loading, empty, first-load error/retry, refresh, and retained-content refresh failure states.
- [ ] Match overall average, subject count, mark count, best/watch summary, and grade bands.
- [ ] Implement subject search and search-empty state.
- [ ] Implement focus/average/name sorting with the same focus score inputs as iOS.
- [ ] Show subject average, mark count, absence percentage, and recent trend direction on each row.
- [ ] Navigate every subject row to its real detail screen and preserve back state.
- [x] Grade parsing, weighted averages, overall average, grade bands, formatted averages, and theoretical-average logic have JVM unit coverage.

## Subject detail, grade history, and calculator

- [ ] Show the subject average hero, absence percentage, subject/temporary notes, and complete mark list.
- [ ] Show mark caption/theme/date/type/type note/weight/points/new-state with optional-field fallbacks.
- [ ] Match iOS mark date parsing and ordering for multiple Bakaláři formats.
- [ ] Implement average-history chart with cloud/local source indication and empty state.
- [ ] Implement grade-history loading by active linked account and time range.
- [ ] Implement mark-input validation and weight controls from 1 through 10.
- [ ] Use the Bakaláři what-if endpoint when enabled; use verified local calculation only when the provider/server requires it.
- [ ] Show better/same/worse predicted result and retain current subject data if prediction fails.

## Absence

- [ ] Implement cache-first initial/loading/loaded/empty/refresh/background-error states.
- [ ] Match total counts and all Bakaláři categories: ok, late, soon, school, distance teaching, unsolved, and missed.
- [ ] Match Subjects/Days/Months segments, grouped totals, empty states, and month chart.
- [x] Day/month aggregation and absence risk calculations have JVM unit coverage.
- [x] Absence what-if projection, duplicate lesson handling, threshold crossing, and unknown-baseline behavior have JVM unit coverage.
- [ ] Resolve per-subject absence from the direct endpoint when present.
- [ ] Port the term-timetable fallback, week progress, timeout, partial-result warning, and cached week reuse.
- [ ] Port partial-day/manual lesson selection, scoped persistence, save/recompute, and validation states.
- [ ] Implement the interactive absence predictor sheet: future timetable loading, date navigation, lesson selection, projected totals, per-subject changes, threshold warnings, edit, and clear.
- [ ] Verify fallback matching for subject aliases, abbreviations, diacritics, unknown lessons, holidays, and malformed dates.

## Timetable

- [x] Implement cache-first initial/loading/loaded/empty/refresh/background-error states.
- [ ] Match previous/current/next week navigation, today shortcut, localized range title, and refresh semantics.
- [ ] Show every school day, holiday/weekend/empty-day state, hour, time range, subject, group, teacher, room, theme, and homework indicator.
- [ ] Show canceled, substitution, room-change, added, and unknown change states without losing original lesson metadata.
- [ ] Implement a tappable lesson detail surface with all available metadata.
- [x] DTO-to-week mapping and current/upcoming widget selection have JVM unit coverage for the imported baseline.
- [ ] Verify duplicate atoms, missing referenced entities/hours, unusual day numbers, empty dates, overnight/device timezone edge cases, and change-type variants.
- [ ] Publish successful timetable refreshes to widget and Wear stores.

## Strava.cz meals

- [ ] Replace the mock repository with the real Strava.cz client, secure session store, scoped menu cache, and linked-account integration.
- [ ] Implement canteen number/username/password connection with validation and readable errors.
- [ ] Restore the meal session and cached menu at startup.
- [ ] Match balance, canteen identity, ordered count, day/meal grouping, price, allergens, meal type, order type, and read-only state.
- [ ] Implement order, cancel, single-main-meal replacement confirmation, insufficient-balance, not-modifiable, and submitting states.
- [ ] Implement disconnect and account-hub link/unlink behavior.
- [ ] Persist and honor the “Show Meals tab” setting; if hidden while selected, return to Today.
- [ ] Keep menu content visible on refresh failure.

## Gradey AI

- [ ] Port status/availability, identity tier, consent, context sections, conversations, messages, and stream-event models.
- [ ] Build context from current Bakaláři marks, absence, timetable, trends, and active school scope with partial/stale/unavailable states.
- [ ] Implement consent explanations, grant, revoke, and local/cloud state reset.
- [ ] Implement conversation list/detail/new chat/delete/delete-all flows.
- [ ] Implement streaming response, stop, retry failed prompt, cancellation, limits/reset time, and support-tier upgrade flow.
- [ ] Render supported Markdown safely and keep the school-data disclaimer visible.
- [ ] Prevent cross-school context reuse with the same scope hashing rules as iOS.
- [ ] Hide or clearly disable AI for local-only guest mode as iOS does.
- [ ] Integrate AI entry points on Today, Subjects, Absence, Timetable, and Meals.
- [ ] Verify authentication, no-context, over-limit, oversized prompt, transport interruption, malformed stream, and app-background behavior.

## Settings and account hub

- [ ] Implement an adaptive settings overview with Account, Connected services, Notifications, Privacy & data, App preferences, and Support & about destinations.
- [ ] Implement profile/avatar summary, full-name edit, Gradey ID/local status, and session sign-out actions.
- [ ] Implement Bakaláři account list/status, add another, activate, reconnect, per-account alerts, unlink confirmation, and sync metadata.
- [ ] Implement Strava.cz connection status, link, retry cloud link, and unlink.
- [ ] Implement device notification permission status/action and lock-screen detail choices.
- [ ] Implement quiet hours, start/end, timezone display, persistence, and cloud update rollback/error handling.
- [ ] Show age-attestation state and legal privacy/terms links.
- [ ] Implement data export creation/share state and two-stage account deletion confirmation.
- [ ] Implement language, Chronically Online, and Show Meals tab preferences.
- [ ] Implement support chat/equivalent, support purchase screen, contact email, GitHub, privacy, terms, credits, version, and build rows.
- [ ] Preserve the hidden version-tap debug unlock and provide safe Android debug actions or mark individual actions `N/A`.
- [ ] Make every visible row/action functional; no dead routes or explanatory placeholder controls.

## Support and purchases

- [ ] Integrate RevenueCat Android offerings, entitlements, restore, purchase, manage-subscription, loading, empty, pending, canceled, success, and error states.
- [ ] Match Standard/Plus tier semantics, monthly/yearly options, savings, renewal copy, and signed-in requirements.
- [ ] Propagate the current support tier to Gradey AI and Wear.
- [x] DIFFERENT — subscription management opens the appropriate Google Play surface rather than Apple subscription settings.
- [ ] Decide and document an Android support-chat equivalent for Intercom, then implement it or mark it `N/A` with product approval.

## Notifications and push

- [ ] Request notification permission only from the onboarding/settings actions that require it.
- [ ] Obtain and refresh the FCM token and register it as platform `android` only with a valid Gradey session.
- [ ] Handle token rotation, sign-out, denied permission, missing Firebase configuration, retry, and duplicate registration safely.
- [ ] Open marks/subjects or timetable from notification/deep-link payloads as appropriate.
- [ ] Apply lock-screen detail and quiet-hours preferences consistently with the backend.
- [ ] Verify foreground, background, terminated, and tapped-notification behavior.
- [x] DIFFERENT — Android uses FCM and notification channels; iOS uses APNs.

## Navigation and deep links

- [ ] Replace the single enum/switch shell with state-restorable Navigation Compose routes and ViewModels.
- [ ] Use stable bottom navigation with Today, Subjects, Absence, Timetable, and optional Meals; Account remains a modal/destination, not a bottom tab.
- [ ] Fix the current context-dependent Meals tab appearance.
- [ ] Preserve selected tab and nested destination across rotation/process recreation where safe.
- [ ] Support `gradey://marks`, `gradey://subjects`, and path variants.
- [ ] Support `gradey://timetable` and path variants from cold and warm starts.
- [ ] Reset relevant feature/navigation state after school account changes and sign-out.
- [ ] Verify every toolbar button, card shortcut, row, retry, dialog action, and back action reaches a functioning destination.

## Design system, Hugeicons, accessibility, and visual fidelity

- [ ] Integrate a maintainable Android Hugeicons Stroke Rounded source and central icon API.
- [ ] Replace obvious `Icons.Default` substitutions throughout production UI with the same or closest iOS Hugeicon.
- [ ] Port the Brand primary/secondary gradient, on-accent ink, aurora background, grouped surfaces, spacing, radii, grade bands, status chips, and risk indicators.
- [ ] Bundle and use Space Grotesk for display titles while retaining Android-readable body typography.
- [ ] Match iOS screen hierarchy and content density while using Android-native touch targets, predictive back, scrolling, dialogs, and sheets.
- [ ] Support light/dark themes, dynamic type/font scale, compact/expanded widths, edge-to-edge insets, keyboard/IME, and screen rotation.
- [ ] Add meaningful content descriptions, headings, traversal order, selected/disabled state, and minimum touch targets.
- [ ] Verify TalkBack and large-font usability on authentication, tabs, detail, settings, and modal flows.
- [ ] Complete a final side-by-side visual audit for every major screen and state.

## Android widget and Wear OS

- [x] Publish a real next-lesson snapshot after successful timetable loads and clear it on school sign-out.
- [x] Match no-snapshot, no-lessons, stale, current, upcoming, room/time, and timetable-change widget states.
- [ ] Wire widget refresh/timeline updates and `gradey://timetable` navigation.
- [ ] Replace Wear demo payloads with phone sync and/or secure direct Bakaláři refresh.
- [ ] Match current lesson progress, upcoming lessons, remaining day, stale/error/signed-out, and manual refresh states.
- [ ] Implement Wear complications for supported Android families where platform APIs allow.
- [ ] Implement support-tier-gated Wear AI or mark it `DIFFERENT`/`N/A` with a documented product decision.
- [x] DIFFERENT — Glance/AppWidget and Wear OS replace WidgetKit/watchOS; exact platform-only layouts and APIs are not copied.
- [x] N/A — macOS widget and macOS app command surfaces have no Android counterpart.

Verification evidence (2026-08-30): a successful Bakaláři timetable refresh now maps the real lesson subject, Prague-local start/end, room, teacher, and change kind into the persisted widget snapshot while retaining other cached weeks. Explicit school sign-out clears both its scoped cache and the widget snapshot. JVM tests cover missing, empty, stale, current, upcoming, and finished selection; multi-week replacement; invalid and overnight times; repository publication; and logout clearing. The Glance surface reads that store, exposes all timetable-change labels, and no longer contains a sample lesson.

Wear implementation evidence (2026-08-30): the hard-coded watch timetable was removed. The phone now publishes a versioned, sub-100-KB Data Layer item after successful timetable loads and publishes signed-out state on logout; it deliberately omits Bakaláři tokens and credentials. The Wear app now has the matching application ID required by Google Play services, receives changes in a path-filtered background listener, rejects unsupported payload schema versions, persists the last valid payload locally, and renders that real payload after cold start. JVM tests verify Prague/overnight lesson mapping, user metadata, timetable changes, and credential omission, and both APKs assemble. The Wear replacement row remains unchecked until delivery is exercised on a paired phone/watch or emulator pair.

## Test, release, and completion gates

- [ ] Add repository tests for login, refresh concurrency, access-token retry classification, refresh rejection fallback, logout, scoped cache, and account switch.
- [ ] Add MockWebServer contract/fixture tests for every Bakaláři endpoint and error class used by Android.
- [ ] Add ViewModel tests for cache-first state, retained-content refresh failure, empty state, retry, expired session, and account change.
- [ ] Add Compose navigation/interaction tests for every visible control and major state.
- [ ] Add Room migration/corruption and encrypted-session migration tests.
- [ ] Run lint, resource checks, unit tests, Compose tests, app build, Wear build, and widget verification cleanly.
- [ ] Search production sources for demo fallbacks, placeholders, TODOs, dead routes, hard-coded secrets, EduPage, and Material icon substitutions; resolve every finding.
- [ ] Perform a clean install and upgrade install on representative phone/tablet API levels.
- [ ] Verify startup, auth/session restoration, real Bakaláři data, offline use, refresh, sign-out/reconnect, account switch, rotation, process death, and deep links end to end.
- [ ] Perform a second independent iOS audit and add any missed functionality to this tracker.
- [ ] Perform the final visual parity audit after functional parity is complete.
- [ ] Confirm every non-`N/A` row above is checked before declaring Android parity complete.
