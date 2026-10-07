# Today screen design QA

Source visual truth: `/Users/filipbukovina/Downloads/Simulator Screenshot - iPhone 17 Pro - 2026-07-11 at 17.31.28.png`

Implementation screenshot: `/Users/filipbukovina/Gradey-android/artifacts/today-implementation-final.png`

Viewport: source 402 × 874 pt (1206 × 2622 px at 3×); implementation 411 × 914 dp (1080 × 2400 px at 420 dpi). The full-view comparison normalizes both captures to 402 × 874 so the responsive Android implementation can be judged against the iPhone composition without system-chrome size skew.

State: signed-in demo Today screen; timetable unavailable; two absence-risk rows; no planned absences; Today tab selected.

## Evidence

- Full-view comparison: `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-final.png`
- Focused absence-risk comparison: `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-final-absence.png`
- Focused hero and Marks comparison: `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-final-hero.png`
- Primary interactions tested on `Medium_Phone_API_36.1`: Marks shortcut/tab, Now and Next → Timetable, Absence Open, Plan absence, Account, Gradey tools, manual Refresh, and return to Today.
- Runtime check: no fatal `AndroidRuntime`/app-process errors after the interaction pass.

## Findings

No actionable P0, P1, or P2 differences remain.

- Fonts and typography: the 22 sp name, 50 sp average, 12 sp hero metadata, 17/13 sp card hierarchy, 16/13 sp risk rows, and 13 sp tracked section labels reproduce the source hierarchy and line wrapping. Roboto replaces SF Pro as the expected native Android typeface; this is an acceptable platform adaptation.
- Spacing and layout rhythm: the main 16 dp margins and gaps match the source. The final measured Android bounds are hero `y=132, h=166`, Marks `y=314, h=62`, Now and Next `y=392, h=96`, Absence Risk `y=504, h=190`, and predictor `y=710`. Cards use 20 dp radii and the floating navigation overlays the predictor as designed.
- Colors and visual tokens: the mint-to-cool-gray background, `#16A083 → #1CA46A` hero, `#17A185` accent, `#FF8D28` warning, white cards, muted gray copy, mint pills, and softened elevation align with the sampled reference palette.
- Image quality and asset fidelity: the reference contains no photographic or custom raster imagery. UI symbols use the closest Material Extended icons; absence rings are live data visualizations, not placeholder artwork. Shapes and icons render sharply at emulator density.
- Copy and content: the visible demo state matches the reference, including Alex Novak, `2,04`, two subjects/four marks, the timetable empty state, absence rows and limit copy, predictor state, and four navigation labels.

## Comparison history

### Pass 1

Evidence: `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-pass1.png` and `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-pass1-absence.png`.

- [P2] Absence descriptions stayed on one line instead of wrapping to the source's two-line rhythm.
- [P2] Card and header shadows were darker than the soft source treatment, and the accent/hero colors were too bright.
- [P2] The Absence navigation icon used a crossed-out calendar instead of a calendar with an exclamation badge.
- [P2] Risk rings displayed raw absence percentages rather than progress toward the configured limit.

Fixes: constrained the risk-copy column, softened elevations, matched sampled colors, switched to a badged calendar icon, and changed ring progress to be threshold-relative.

### Pass 2

Evidence: `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-pass2.png` and `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-pass2-absence.png`.

- The typography, wrapping, shadows, color, and navigation-icon findings were resolved.
- [P2] The ring sweeps still did not represent the same limit-relative proportions visible in the source demo state.

Fix: passed the real per-row threshold into the ring and normalized the sweep against it.

### Pass 3

Evidence: `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-pass3.png` and `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-pass3-absence.png`.

- [P2] The chart logic was correct, but the visual demo fixture used a 30% limit, producing shorter arcs than the 25% source state.

Fix: aligned the demo fixture's threshold and lesson counts with the reference while preserving the displayed 18%, 10%, four-lessons-left, and nine-lessons-left values.

### Final pass

Evidence: `/Users/filipbukovina/Gradey-android/artifacts/today-comparison-final.png` and focused crops listed above.

All earlier P2 findings are visibly resolved. Remaining differences are limited to expected Android system chrome, Roboto metrics, and Material glyph contours; these are P3 platform polish rather than design drift.

## Implementation checklist

- [x] Match responsive layout, spacing, sizes, radii, elevation, and fixed bottom navigation.
- [x] Preserve live grade, timetable, absence, user, refresh, and navigation behavior.
- [x] Match empty states, risk text, demo copy, and threshold-relative rings.
- [x] Verify build, unit tests, primary taps, and fatal runtime logs.

## Follow-up polish

- [P3] A custom licensed font or bespoke icon set could reduce the remaining SF Pro/SF Symbols versus Roboto/Material differences, but native Android rendering is preferable for the current app.

final result: passed

---

# Timetable design QA

## Visual truth and test states

Source images:

- `/Users/filipbukovina/Downloads/Simulator Screenshot - iPhone 17 Pro - 2026-07-12 at 16.48.29.png` — weekly overview
- `/Users/filipbukovina/Downloads/Simulator Screenshot - iPhone 17 Pro - 2026-07-12 at 16.48.32.png` — Matematika lesson sheet

Final implementation captures:

- `/Users/filipbukovina/Gradey-android/artifacts/timetable-overview-final.png`
- `/Users/filipbukovina/Gradey-android/artifacts/timetable-sheet-final.png`

Final full-view comparisons:

- `/Users/filipbukovina/Gradey-android/artifacts/timetable-comparison-overview-final.png`
- `/Users/filipbukovina/Gradey-android/artifacts/timetable-comparison-sheet-final.png`

Viewport: source 402 × 874 pt (1206 × 2622 px at 3×); implementation 1080 × 2348 px at 430 dpi, which is the same 402 × 874 logical viewport. References were normalized to the implementation pixel dimensions before side-by-side review.

## Findings

No actionable P0, P1, or P2 differences remain.

- Layout: the measured header actions, 40 dp week controls, five 52 × 66 dp day cells, divider, 72 dp time rail, 313 dp lesson cards, and five-tab floating navigation align with the overview reference. Topic rows use the taller 83 dp card and lessons without topics use the 68 dp card.
- Lesson sheet: the custom modal starts at the same 414 dp vertical position, keeps an 8 dp outer margin, uses the measured 48 dp corners, and aligns the handle, title, 96 dp hero, and 153 dp details card with the reference.
- Typography and icons: the compact native Android hierarchy now tracks the SF reference closely. Material outlined room/book glyphs are the closest available platform equivalents; remaining glyph and Roboto/SF differences are P3 platform character rather than drift.
- Color and depth: the aqua-to-cool-gray field, right mint glow, teal-to-green selections, white cards, muted text, red notice dots, 20% modal scrim, and softened elevations match the sampled treatment.
- Data and behavior: the screen renders Mon–Fri from a mapped timetable response. Week arrows load adjacent weeks, day cells select their own schedules, refresh reloads the visible week, and each lesson opens teacher/room/topic details. Changed or canceled lessons retain visible and semantic change state, and unavailable data is distinct from a free day.

## Comparison history

### Pass 1

Evidence: `artifacts/timetable-comparison-overview-first.png` and `artifacts/timetable-comparison-sheet-first.png`.

- [P2] Android text and card shadows were heavier than the supplied iOS reference.
- [P2] The week range included excess spacing around the dash.
- [P2] The lesson sheet extended to the viewport bottom instead of preserving the reference's 8 dp margin.
- [P2] The filled room glyph was less faithful than the source's outlined door treatment.

Fixes: reduced type scale/weight where the paired captures showed a mismatch, softened elevation, compacted the week label, inset and resized the modal, and switched metadata to outlined Material glyphs.

### Final pass

Evidence: the two final comparisons listed above.

All earlier P2 findings are visibly resolved. The only remaining differences are the Android status/navigation chrome, native font rasterization, and Material versus SF Symbol contours.

## Verification

- [x] `./gradlew --no-daemon test :app:lintDebug :app:assembleDebug`
- [x] Monday overview renders the four reference lessons with exact times, teachers, room, and topics.
- [x] Tuesday selection renders its own four-lesson data; next/previous arrows move between `Jul 6–10` and `Jul 13–17`.
- [x] Lesson sheets were checked for both topic and topic-free states; Android Back and outside-dismiss behavior work.
- [x] Marks → Timetable tab navigation and visible-week refresh were exercised on the final APK.
- [x] Runtime log contains no fatal exception or app ANR after the complete interaction pass.
- [x] Emulator remains running on the Timetable overview at the 402 × 874 reference viewport.

final result: passed

---

# Marks and Absence design QA

## Visual truth and test states

Marks source images:

- `/Users/filipbukovina/Downloads/Simulator Screenshot - iPhone 17e - 2026-07-12 at 14.52.28.png` — overview
- `/Users/filipbukovina/Downloads/Simulator Screenshot - iPhone 17e - 2026-07-12 at 14.52.37.png` — Czech detail, top
- `/Users/filipbukovina/Downloads/Simulator Screenshot - iPhone 17e - 2026-07-12 at 14.52.41.png` — Czech detail, scrolled

Marks implementation captures:

- `/Users/filipbukovina/Gradey-android/artifacts/marks-list-final2.png`
- `/Users/filipbukovina/Gradey-android/artifacts/marks-detail-top-final.png`
- `/Users/filipbukovina/Gradey-android/artifacts/marks-detail-scrolled-final.png`

Marks full-view comparisons:

- `/Users/filipbukovina/Gradey-android/artifacts/marks-list-comparison-final.png`
- `/Users/filipbukovina/Gradey-android/artifacts/marks-detail-top-comparison-final.png`
- `/Users/filipbukovina/Gradey-android/artifacts/marks-detail-scrolled-comparison-final.png`

Marks viewport: source 390 × 844 pt; implementation 1024 × 2216 px at 420 dpi, normalized to the source dimensions for comparison.

Absence source images:

- `/Users/filipbukovina/Downloads/Simulator Screenshot - iPhone 17 Pro - 2026-07-12 at 16.07.54.png` — Subjects
- `/Users/filipbukovina/Downloads/Simulator Screenshot - iPhone 17 Pro - 2026-07-12 at 16.07.51.png` — By days
- `/Users/filipbukovina/Downloads/Simulator Screenshot - iPhone 17 Pro - 2026-07-12 at 16.07.57.png` — By months

Absence implementation captures:

- `/Users/filipbukovina/Gradey-android/artifacts/absence-subjects-final.png`
- `/Users/filipbukovina/Gradey-android/artifacts/absence-days-final.png`
- `/Users/filipbukovina/Gradey-android/artifacts/absence-months-final.png`

Absence full-view comparisons:

- `/Users/filipbukovina/Gradey-android/artifacts/absence-subjects-comparison-final.png`
- `/Users/filipbukovina/Gradey-android/artifacts/absence-days-comparison-final.png`
- `/Users/filipbukovina/Gradey-android/artifacts/absence-months-comparison-final.png`

Absence viewport: source 402 × 874 pt; implementation 1080 × 2348 px at 430 dpi, normalized to 1206 × 2622 px for comparison.

## Findings

No actionable P0, P1, or P2 differences remain.

- Layout: the measured headers, cards, segmented controls, chart plots, rows, and fixed bottom navigation align with the supplied viewport states. Absence uses four bottom tabs while the supplied Marks state exposes Meals as a fifth tab.
- Typography: hierarchy, weights, wrapping, and alignment reproduce the references. Roboto and Material glyph contours remain the expected native Android equivalents of SF Pro and SF Symbols.
- Color and depth: the localized aqua background glows, cool-gray lower canvas, white cards, subtle elevations, teal/green/orange attendance categories, progress rails, and one-pixel dividers match the sampled reference treatment.
- Content: Marks derives `2,04`, `2,30`, `1,78`, the Czech mark card, absence percentages, and calculator result from shared demo domain data. Absence derives all `22` hours, status totals, five dates, five months, bars, and rows from the same attendance records.
- Behavior: Marks overview sorting, subject navigation/back, scrolling, editable mark prediction, and weight controls work. Absence Subjects, By days, and By months are selectable tabs with accessibility roles and live recomposition.

## Comparison history

### Marks pass 1

Evidence: the `artifacts/marks-*-comparison-pass1.png` files.

- [P2] Detail back glyph, header title metrics, hero-number scale, chip widths, x-axis labels, background depth, and card shadows differed from the references.

Fixes: used a chevron glyph, tuned type and chip geometry, moved chart labels, localized the background glows, and softened elevations.

### Absence pass 1

Evidence: the `artifacts/absence-*-comparison-pass1.png` files.

- [P2] The initial horizontal glow tinted the lower canvas instead of fading to cool gray.
- [P2] Header/title metrics and card elevation were stronger than the source.

Fixes: replaced the full-height glow with measured top-right and lower-left radial glows, adjusted native type metrics, and reduced content elevation.

### Absence pass 2 and final

Evidence: the `artifacts/absence-*-comparison-pass2.png` and `artifacts/absence-*-comparison-final.png` files.

All P2 findings were resolved. Remaining differences are limited to Android status/navigation chrome and native font/icon contours.

## Verification

- [x] `./gradlew --no-daemon :core-domain:test :app:assembleDebug`
- [x] Marks calculator: entering `1` and selecting Weight 2 produced the expected `1,65` predicted average.
- [x] Absence tabs: Subjects, By days, and By months all rendered from the same 22-hour fixture.
- [x] Navigation: four-tab Absence and five-tab Marks configurations both exercised.
- [x] Runtime log: no fatal exception or ANR after the complete interaction pass.
- [x] Emulator left running on the Absence Subjects state at the 402 × 874 reference viewport.

final result: passed
