# Design QA — broad school search

Reference:
- Previous login screenshot with eight `soukroma` results.
- Redesigned login screenshot with only two `Soukroma` results.

Verified implementation:
- A broad school query exposes all eight matching rows in the UI test fixture.
- Results use a bounded, vertically scrollable list instead of expanding the whole login form.
- Manual URL and demo controls are hidden while the search field is active, keeping results readable.
- Incomplete municipality refreshes are rejected and cannot replace the complete cached directory.
- Legacy partial caches refresh once after this update.

Blocking issues: none.

final result: passed

## Design QA — Settings-style Timetable and Setup Flows

Comparison target:

- Source visual truth: the verified Settings overview at `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/hugeicons/dark/settings-overview.png`.
- Scope: timetable summary, navigation and lesson cards; school selection and credentials; Strava.cz connection; welcome, account, notification, meals and ready onboarding steps.

Findings:

- The requested screens now reuse the Settings-local background, adaptive teal surface, 28-point radius, 20-point margin, Space Grotesk heading and compact Hugeicons language.
- Large gradient icon tiles and heavy card shadows were removed from setup flows. Visible hero and row icons now resolve through the Hugeicons-backed `GradelyIcon` mapping at 14–17 points while retaining 44-point interaction targets.
- Timetable lesson cards use flatter 28-point surfaces with reduced subject tiles, quieter borders and no drop shadow. Current lessons and timetable changes retain their semantic emphasis.
- All existing form fields, loading states, provider switching, school search, credential navigation, error alerts, onboarding progress and connection callbacks remain in place.
- Swift parsing passed for all six touched view files and their shared component definitions. The full Xcode build was intentionally not expanded into a test matrix; dependency resolution from the iCloud-hosted workspace did not complete within the lightweight verification window.
- A fresh screenshot suite was intentionally skipped to honor the request to minimize tests and tool use. The implementation was checked against the already verified Settings source capture and shared component values.

Blocking issues: none identified in the implementation pass.

final result: passed

## Design QA — Quipee-inspired Settings redesign

Reference and capture:

- Visual reference: supplied Quipee Settings screenshot.
- Final Gradely capture: iPhone 17 Pro, iOS 26.5, 402 × 874 points (1206 × 2622 pixels), dark mode, English, signed-in account with one active school, disconnected canteen, and quiet hours enabled.
- Side-by-side comparison: `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/quipee-reference-vs-gradely-final.png`.
- Supporting captures: light mode at `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/light/B159A459-4592-4793-87F9-01517EE2A8B1.png` and iPad split view at `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/ipad/B73A1082-CB7C-44A8-A8BD-BA0796ED3920.png`.

Visual comparison:

- The first implementation pass exposed an oversized title, surfaces that were too gray and bright, and subtitles that wrapped more readily than the reference.
- The final pass uses a 36-point Space Grotesk title, darker teal-tinted settings-local surfaces, compact footnote subtitles, 20-point horizontal margins, approximately 28-point corner radii, 84-point minimum rows, unboxed SF Symbols, and inset dividers.
- The hierarchy and rhythm now track the Quipee reference while intentionally preserving Gradely's modal close action and Gradely-specific destinations.
- The final compact overview has no clipping, the Support & About row remains visible and usable, and the only overview status decoration is the conditional Connected Services warning.

Functional and accessibility coverage:

- The profile card routes to Account; all six existing destinations remain reachable.
- Named, missing-name, failed-save, and guest states are covered. Name input trims surrounding whitespace, accepts 1–80 grapheme clusters, preserves failed drafts, and propagates successful saves immediately.
- Email is absent from the overview and remains read-only in Account details.
- The circular close control dismisses modal Settings and is absent during required setup.
- Czech localization and the largest accessibility text size keep the overview and final destination navigable.

Platform verification:

- Focused iPhone Settings UI suite: passed.
- Dark-mode 402 × 874 visual capture: passed.
- Light-mode 402 × 874 visual capture: passed.
- iPad `NavigationSplitView` capture and selected Account detail assertion: passed.
- macOS `GradelyMac` arm64 build: passed.
- Auth-client and view-model unit coverage for refresh, update, rollback, Apple-name persistence, validation, save errors, cache refresh, and immediate propagation: passed.

Blocking issues: none.

final result: passed

## Design QA — Settings Hugeicons refinement

Reference and capture:

- Visual reference: supplied Quipee Settings screenshot.
- Final Gradely capture: iPhone 17 Pro, iOS 26.5, 402 × 874 points, dark mode.
- Final side-by-side comparison: `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/hugeicons/quipee-reference-vs-gradely-hugeicons.png`.
- Supporting appearance captures: light mode at `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/hugeicons/light/settings-overview.png` and iPad split view at `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/hugeicons/ipad/settings-overview.png`.

Refinement history:

- Replaced Settings SF Symbols with the official local Hugeicons Pro Stroke Rounded package on iOS and macOS.
- Reduced overview row glyphs from 22-point symbols in 44-point slots to 17-point Hugeicons in 32-point slots.
- Reduced disclosure glyphs to 14 points and the close glyph to 15 points while retaining 44- and 48-point interactive targets.
- Converted overview, navigation, status, detail, and action glyphs so Settings uses one consistent icon language.
- The final comparison shows quieter icon weight and scale, intact hierarchy, no clipping, and a fully visible Support & About row.

Verification:

- Final iOS and macOS builds: passed.
- Final dark-mode 402 × 874 capture and combined visual comparison: passed.
- Light mode and iPad split-view visual checks: passed.
- Named, missing-name, failed-save, guest, required-setup, Czech localization, accessibility text, and destination-routing UI checks: passed.
- Auth-client and view-model test suites: passed.

Blocking issues: none.

final result: passed

## Design QA — Settings-style Support and Credits

Comparison target:

- Source visual truth: the verified Settings overview at `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/hugeicons/dark/settings-overview.png`.
- Final dark implementations: Support at `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/support-credits/support.png` and Credits at `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/support-credits/credits.png`.
- Full-view comparison evidence: `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/support-credits/settings-support-credits-comparison.png`.
- Light-mode evidence: `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/support-credits/light/support.png` and `/Users/filipbukovina/.codex/visualizations/2026/07/30/019fb3c4-d66a-7eb3-bff2-e50a683e0e28/settings-qa/support-credits/light/credits.png`.
- All captures use an iPhone 17 Pro viewport at 402 × 874 points and 1206 × 2622 pixels (3× density), with no density normalization required.
- State: English, signed-in mock account, dark and light appearances, loaded mock tip products.

Findings:

- No remaining P0, P1, or P2 differences. Support and Credits now share the Settings hierarchy, visible density, icon scale, margins, radii, surface treatment, and dismissal affordance.
- Fonts and typography: all three screens use the same 36-point Space Grotesk display title, native headline hierarchy, compact footnote support copy, tracked uppercase metadata, and readable wrapping.
- Spacing and layout rhythm: 20-point screen margins, 24-point section gaps, 28-point surfaces, 84-point minimum action rows, inset dividers, and 48-point close targets match the source Settings rhythm.
- Colors and visual tokens: the same dark teal background, adaptive teal-tinted surfaces, semantic primary/secondary text, and brand accent are used in both appearances with no clipping or contrast failure visible.
- Image and icon fidelity: all navigation, action, contact, status, and disclosure glyphs use the bundled Hugeicons Stroke Rounded face at the compact Settings scale. No new raster imagery or placeholder asset was introduced; the existing OpenSide typographic wordmark was preserved.
- Copy and content: support purchase labels, prices, explanatory copy, team roles, contacts, attribution, and links remain unchanged and localized.

Focused-region evidence:

- The individual Support and Credits captures were inspected at full resolution for the circular close target, Hugeicons alignment, OpenSide wordmark, contact rows, dividers, price rows, attribution copy, and text wrapping. Separate crops were unnecessary because every relevant region remained clearly readable in the 1206-pixel-wide captures.

Comparison history:

- Initial dark Credits capture exposed a P2 layout issue where the close control could resolve outside the visible header width.
- The header and scroll content were expanded to the available width; a subsequent cross-appearance pass exposed that the HStack arrangement was still fragile in light mode.
- The final header uses a full-width trailing overlay with 60 points reserved for the close target. Revised dark and light captures show the close control consistently aligned and fully visible.

Interaction and platform verification:

- Support and Credits navigation, modal dismissal, loaded tip rows, and all expected content identifiers: passed.
- Existing mock support purchase through the thank-you state: passed.
- Final dark-mode and light-mode visual UI tests: passed.
- iOS simulator build and macOS `GradelyMac` build: passed.

Blocking issues: none.

final result: passed

## Design QA — School Login Primary Action

Comparison target:

- Source visual truth: `/Users/filipbukovina/Downloads/Screenshot 2026-08-05 at 9.51.49 AM.png`.
- State: dark-mode school-selection screen, Bakaláři selected, no school selected, primary action disabled.
- Intended change: remove the production demo-account entry point and replace the divided bottom action bar with a standalone Settings-style primary action.

Findings:

- Source evidence shows the primary action attached to a full-width bottom panel with a horizontal divider, creating an outdated toolbar appearance.
- The implementation removes the divider and panel background. The action now floats directly over the screen background with 20-point margins, a 58-point target, 22-point radius, compact Hugeicons arrow, subtle border, and minimal elevation.
- The demo account button is hidden in production. Its view-model behavior and UI-automation path remain intact behind the existing `-uiTestingMockAPI` launch argument.
- Fonts, copy, provider selection, school search, manual URL entry, enabled/disabled behavior, accessibility identifiers, and credential navigation remain unchanged.
- Swift parsing and Xcode file diagnostics passed with no issues.

Visual evidence:

- A revised implementation screenshot could not be captured because the Xcode visual runner timed out while resolving the iCloud-hosted workspace.
- Full-view and focused-region comparison are therefore blocked; no visual-match claim is made.

Blocking issue: revised runtime capture unavailable.

final result: blocked
