# Gradey × Siri

Siri and Shortcuts can read the next lesson, a day's schedule, a subject's averages or recent grades, and incomplete Planner items. The Add Planner item action supports all existing item types and confirms the resolved details before saving. Open actions navigate to subjects, grades, lessons, and Planner items, including after a cold launch.

Example English phrases: “Next lesson in Gradey”, “My schedule in Gradey”, “My grades in Gradey”, “My Planner in Gradey”, and “Add a Planner item in Gradey”. English and Czech action metadata and responses are included; voice recognition depends on Apple's supported Siri languages. Shortcuts exposes additional date, subject, search, type, and notes parameters.

## Architecture and privacy

`GradelyApp` creates one `AppEnvironment` shared by its windows and registers it and `GradeyIntentService` with `AppDependencyManager`. The service reuses `SchoolRepository`, `SchoolSnapshotStore`, `GradeMath`, and `PlannerStore`. These actions make no Gradey AI generation requests and consume no Gradey Compute.

Direct actions require device authentication and completed app setup. Entity identities contain an opaque account/student scope; resolution and writes recheck that scope and the repository's session generation after asynchronous work and confirmation. Unscoped personal Planner items retain the app's existing visibility rules. Name queries return every matching subject so Siri can disambiguate.

Grades refresh after five minutes; timetables after fifteen. Siri waits at most eight seconds for refresh, then uses available cache with its original update timestamp. Missing days or unreadable caches report unavailable rather than an empty schedule. School averages and Gradey calculations remain separately labelled; provider grade display formats are preserved.

Planner creation persists locally before Calendar export. It uses existing Calendar permission and leaves failed or unauthorized exports pending for the app; Siri never requests Calendar permission. Existing in-app callers retain their permission behavior. One UUID is allocated per confirmed execution. Native reminder requests create Planner tasks and reject unsupported recurrence, locations, attachments, tags, URLs, flags, and sections before saving.

## Discovery

In **Settings → Privacy & Data**, “Make school content discoverable to Siri and Spotlight” is off by default. Enabling it shows a disclosure before indexing cached subject/grade summaries, lessons for this and next week, and incomplete relevant Planner items. The dedicated protected index excludes credentials, teacher identifiers, private notes, and chat history. Indexed summaries include freshness information. Disabling, signing out, changing accounts/students, clearing caches, or deleting content triggers serialized replacement/purge; reindex requests are supported. Onscreen entity associations use the same preference.

OS 26 retains custom App Entities and Shortcuts. Availability-gated OS 27 adapters expose scheduled lessons as calendar events, actionable Planner items as reminders, and navigation through `.system.open`. Grades remain custom entities; note-only Planner items are not misrepresented as reminders. Classroom names remain in the lesson summary rather than being represented as street addresses.

## Validation

Run the GradelyTests suite and GradeySiriUITests on an iOS simulator, plus a GradelyMac build. `Scripts/validate-siri-metadata.py /path/to/Gradey.app` checks extracted actions, authentication, shortcuts, schema availability, and metadata translations. `python3 Scripts/sync-co-localizations.py --check` verifies existing CO catalog completeness.

The implementation includes tests for ambiguity, provider grade formats, stale/offline responses, cancellation, account changes, EduPage child isolation, canceled lessons, missing versus empty schedules, timeout fallback, time zones/DST, all-day dates, confirmation, local storage failures, Calendar export failures, and discovery purge races. UI tests cover cold/repeated scoped navigation and the discovery consent toggle.

Verified on 2026-09-16 with Xcode 27:

- iPhone 18 Pro simulator: all 423 unit tests and four UI tests passed (two Siri flows plus two existing Planner regressions).
- iPad Pro 13-inch (M5) simulator: all 423 unit tests and both Siri UI flows passed. The first discovery test attempt timed out while Xcode acquired a background assertion; the isolated retry passed without a source change.
- iOS build-for-testing and macOS Debug build passed. Extracted metadata on both platforms contains 14 authenticated actions and six App Shortcuts; native schemas are gated to OS 27. Packaged minimum OS versions remain 26.0, with iPhone and iPad device families included.
- English/Czech/CO metadata validation, catalog completeness, and `git diff --check` passed. SHA-256 comparison matched the 29 scoped source/configuration files between the original checkout and the local validation mirror; existing catalog entries and preexisting checkout changes were preserved.

Local logs, result bundles, baseline backups, and the source hash manifest are in `/Users/filipbukovina/Developer/Gradey-Siri-Validation/`. Successful iPhone results are in `Siri-Verified-iPhone.xcresult`; the iPad discovery retry is in `Siri-iPad-Discovery-Retry.xcresult`. The complete iPad unit and navigation outcomes are also recorded in `siri-final-ipad-tests.log`.

Physical-device Siri voice invocation, confirmation/disambiguation presentation, and system Spotlight search should be checked with a signed build on both supported OS generations. Automated tests and metadata extraction do not establish those system-level results.

RevenueCat is pinned to [5.78.0](https://github.com/RevenueCat/purchases-ios/releases/tag/5.78.0) (from 5.77.0) for its Xcode 27 compiler compatibility fix. OS minimums are unchanged. No Watch integration, school-provider writes, backend deployment, or App Store submission is included.
