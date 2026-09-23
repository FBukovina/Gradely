# Gradey 2.2 Intelligence implementation

The existing SwiftUI app now shares cached school snapshots and prepared grade calculations across Today, Subjects, Subject Detail and contextual AI. The five tabs, personal Planner, one-way Calendar export, existing grade pushes and Firebase chat ownership remain in place.

## Code and provenance

Implementation was isolated in `/Users/filipbukovina/Developer/Gradey-2.2-xpqnb0zz`, using preserved Git baselines of both current working trees. App baseline commit `687d217` includes the existing Planner/privacy changes; backend baseline commit `1245114` includes the previously untracked Gradey AI implementation. Only implementation files are copied back, after comparing original-file SHA-256 hashes with those baselines. No production configuration, function, database row or App Store state was changed.

- `SchoolRepository` fences token refresh, retry, cache and widget/Watch publication by session generation and identity. Failed manual refreshes retain existing disk caches. Provider reads coalesce by identity, source and timetable week/kind.
- `SchoolSnapshotStore` hydrates synchronously, shares in-flight refreshes, publishes individual successful sources, and preserves last-good timestamps. Freshness is five minutes for marks and fifteen minutes for other school sources. The observation sidecar is additive and rebuilds a quiet baseline after missing or incompatible state.
- `GradeMath` prepares immutable inputs. The existing single-grade calculator and the new ten-row simulator reuse those inputs. Target suggestions use inclusive `average <= target`, forward simulation, fractional recorded weights and the existing modifier mapping. Provider averages remain separate from reconstructed arithmetic.
- `SubjectInsightEngine`, `PlannerEventProjection` and `TodayInsightEngine` share factual summaries, observation history and exact scoped Planner references. Today ranks at most three attention rows. Reconstructed grade contribution is labelled separately from observed history.
- `GradeyAIContextBuilder` captures selected context and filters it before size limits. General chat attaches no school record automatically. A selected test's notes require a separate choice. Purpose changes start a new conversation, and account/school scope is checked again after authentication awaits. The Watch relay sends general chat without automatically attaching school records; focused school context is selected on iPhone, and older broad-context Watch conversations are not reused.
- Existing Firebase reservations now own Compute, paid entitlement verification, canonical billing principals, charge-once settlement, refunds, provider expense and recovery. The app displays server balances; local purchases cannot grant an allowance.
- Optional daily Planner reminders default off, aggregate tomorrow's known items at 18:00, respect quiet/privacy preferences and reconcile edits, account changes and foreground activation. Typed notification routing retains cold-launch destinations and forwards unrelated notifications to the existing delegate.

## Compatibility decisions

Bakaláři sessions retain their existing scope. Linked EduPage scopes include the exact student identity so one child's Planner items and school observations cannot appear for another child. Older linked EduPage Planner entries remain in the full Planner, but must be explicitly relinked before they contribute to scoped Today/AI/reminders. School history without child identity is not comparable across students; local grade timelines and observations remain available.

The `grade-history` endpoint now limits the newest 1,000 observations and returns them chronologically, instead of truncating away recent history. Existing storage formats remain readable. New insight state is limited to 100 change records and thirty days; initial import, disappearing grades/subjects and incompatible calculation bases establish a baseline without alerts.

The Firebase v2 contract is additive. Legacy 2.1 shapes remain accepted. Immutable retries recover existing outcomes; a deliberate attempt after a confirmed failure uses a new ID. Pending recovery stores identifiers and a hash, not another school-context archive. Full generation recovery runs separately from daily content retention.

All shipping app, widget, Watch and complication targets are set to **2.2 (37)**. Test bundles retain their independent test metadata. Grade distribution and broader period analysis are deferred; no purchased Compute wallet or additional AI provider was added.

## Verification

- Swift unit suite: **382 tests passed across 42 suites**, including the seven new Watch privacy/scope tests and localized all-day date regression.
- Firebase: **75 tests passed** (44 unit, 25 Gradey emulator and 6 shared-project isolation/rules tests).
- iPhone UI: **four tests passed** for existing login/Subjects/calculator compatibility, the new offline simulator, Czech large-text/dark Today, and required privacy-sheet acceptance/dismissal.
- iPad UI: both new Intelligence checks passed again against the final test build. Exported simulator screenshots were inspected.
- Unsigned iOS Release and watchOS Simulator Release builds passed; the final shared macOS Debug build passed. The iOS Release runtime configuration validator passed on the built containing/embedded bundles.
- Containing and embedded app/widget/Watch/complication metadata reads **2.2 (37)**. Six release-validator fixtures passed, including rejection of version mismatches, unresolved configuration and server-only keys.
- Local Deno check for `grade-history` and Git whitespace checks passed. All 107 added localization keys have English and Czech entries.

Evidence is retained under the isolated implementation directory: `FinalRegression-Verified.xcresult`, `UI-iPad-Final.xcresult`, `ios-release-final.log`, `mac-build-verified.log`, `watch-release-build.log`, and `verified-bundle-metadata.json`. Backend test output is recorded in the task transcript.

Runtime checks use mock school data and the explicit demo Firebase emulator project. No billable provider generation was used. The privacy policy source is a coordinated 2.2 draft, not a claim that the public policy has been published.

### September 11 localization correction

The initial UI verification missed both Chronically Online language variants. New 2.2 keys lacked `en-CO`/`cs-US` entries, so native SwiftUI rendered internal keys and the action buttons wrapped those keys. The correction fills missing dialect entries while preserving authored copy, adds base-language fallback for Bundle lookups, and tests native lookup across all four modes, including plural and format arguments. `python3 Scripts/sync-co-localizations.py --check` rejects missing dialect entries; run `--write` after adding base translations. Xcode extraction metadata from the original checkout is retained.

Today actions now stack when their complete labels do not fit horizontally and retain at least 44-point tap targets. Current and next lessons both remain visible with times and room information. Ended timetable changes expire, exact duplicate changes collapse, and distinct consecutive periods remain separate.

Follow-up checks: 395 Swift tests passed, and all four Intelligence UI tests passed, including English CO Today/simulator and Czech CO at the largest accessibility text size. Screenshots were exported and inspected; the shared macOS Debug build also passed. Evidence is in `LocalizationFix/FinalUnits.xcresult`, `LocalizationFix/FinalUI.xcresult`, `LocalizationFix/final-screenshots`, and `LocalizationFix/mac-build.log` under the isolated implementation directory. These local checks do not update an already installed phone build.

### September 11 whole-catalog copy and AI follow-up

The language review now covers the entire 979-key app catalog in English, Czech and both Chronically Online modes. Compared with `b4e8b772`, 729 existing translations changed across 249 keys, and 12 new AI error/context keys added 48 translations. The authored CO catalog also received 25 matching translation updates across 15 keys. Czech uses consistent informal wording; English is more natural; deliberate CO slang remains. Count labels avoid incorrect singular/plural combinations, and format-token types, counts and argument positions are unchanged. The four smaller permission, widget, Watch and complication catalogs were also reviewed (85 existing entries). Their 12 copy corrections cover lesson terminology, purchase restoration, subscription names, school sign-in and brand casing; Watch adds nine localized AI error keys.

The pass also corrects behavior-facing copy: Compute replaces the old message allowance wording; AI and Planner disclosures explain selected school-data sharing, optional test notes, and Google Firebase/Microsoft Azure OpenAI processing; Strava copy distinguishes saved sessions from passwords; guest sign-out no longer claims to leave guest mode; and dormant age-gate text now describes the existing parental-consent flow. Empty timetable and absence states no longer imply a wholly free day or absence safety without data.

Functional corrections include:

- AI reply requests and reset times use the selected app language. Stable backend error codes and stale-context section names display localized UI text instead of server diagnostics or internal identifiers. Watch maps rejected requests and failed streams to its own English/Czech copy, including a localized fallback for unknown remote errors; transport codes and behavior remain unchanged.
- CO transformation preserves product names and Compute/AI/UTC casing at word boundaries, without changing matching substrings inside ordinary words. The synchronization check now rejects authored/native CO copy mismatches as well as missing dialect entries.
- The AI action/cost row stacks when needed. At accessibility text sizes, the welcome controls stack and context/messages share a scrollable area above the composer; the refresh control retains its full icon and tap target.

Verified results for this follow-up:

- **397 Swift tests passed across 43 suites** in `CopyPolish/Regression2.xcresult` (`regression2.log`).
- All four AI language checks passed: standard English/Czech in `CopyPolish/FinalAIUI.xcresult` and both CO variants at the largest accessibility size in `CopyPolish/AccessibleAI-Verified.xcresult`. The latter verifies reachable context selection, a visible composer, readable Compute and mock consent; its exported screenshots were inspected.
- All **four existing Intelligence UI tests passed** in `CopyPolish/Regression.xcresult` (`regression.log`).

- The final macOS Debug and watchOS Simulator Release builds passed (`CopyPolish/mac-build.log` and `CopyPolish/watch-build.log`). Catalog completeness, authored/native CO agreement, format-token preservation and Git whitespace checks passed.

These results come from the named focused runs, rather than a new full release acceptance run. Earlier AI accessibility failures prompted the layout fixes; final CO checks use controlled scrolling to avoid skipping controls in long content. UI checks use mock school/AI data and do not send a generation. The earlier release and production-rollout boundaries remain unchanged. The corrected sources are copied back with original-file hash guards; installed device builds require a rebuild/update.

## Production rollout gates

The read-only Firebase baseline showed active Gradey functions with legacy 5/30 guest/linked allowances, no Compute catalog and an existing USD 900 spending ceiling. The new Supabase verification and RevenueCat server secrets were absent. Preserve the live ceiling and counters.

Before enabling AI 2.2, follow `opensocial/functions/README-Gradey-Compute.md`: provision the configured Gradey Auth URL and server secrets; verify RevenueCat account/Support mappings, current Azure pricing and paid-plan economics; stage the versioned priced catalog with the new matching consent version and Azure processor metadata; verify actual index readiness; and use an explicit Gradey-only deployment allowlist and controlled canary. The code rejects missing pricing, old consent metadata and invalid supplied identity proof.

Live RevenueCat offering/purchase/restore verification, controlled production account checks, public policy publication, signing/App Store upload and release approval are not performed by this implementation task. Supabase connector reauthentication prevented a live history query; its changed function passed local Deno type checking. Manual VoiceOver review and physical-device notification delivery remain separate from automated local checks.
