# Gradely School Connection Two-Stage Flow — Design QA

## Evidence

- Source visual truth: `/Users/filipbukovina/Desktop/Simulator Screenshot - iPhone 17 Pro - 2026-07-24 at 23.53.43.png`
- School-selection implementation: `/Users/filipbukovina/.codex/visualizations/2026/07/21/019f83ff-2133-7860-b713-1b642c8ebd72/onboarding-school-selection-final.png`
- Credentials implementation: `/Users/filipbukovina/.codex/visualizations/2026/07/21/019f83ff-2133-7860-b713-1b642c8ebd72/onboarding-school-credentials-final.png`
- Full-view comparison: `/Users/filipbukovina/.codex/visualizations/2026/07/21/019f83ff-2133-7860-b713-1b642c8ebd72/onboarding-school-two-stage-comparison.png`
- Viewport: iPhone 17 Pro, 402 × 874 pt.
- Source pixels: 1206 × 2622 at 3× density.
- Implementation pixels: 1206 × 2622 at 3× density for both states; no density normalization was required.
- State: onboarding step 2 of 4, English, dark appearance, Bakaláři demo school selected for the credentials-state capture.
- Focused comparison: not required because the equal-density three-column comparison keeps the stage control, form fields, labels, selected-school summary, icons, and primary actions legible.

## Findings

- No actionable P0, P1, or P2 findings remain.
- P3 follow-up: the manual school-address help could become a sheet in a future iteration if analytics show that expanding instructions inside the selection card is too dense.

## Comparison History

1. The source screen had a P1 information-architecture issue: provider selection, school discovery, manual URL help, credentials, demo access, and final connection were presented in one dense form. The redesign separates these into a school-selection state and a credentials state with a persistent two-stage indicator.
2. The first implementation capture exposed a P1 state-transition issue where the onboarding progress header could be visually displaced while switching between the internal stages. Stable screen identities were added, and the parent Back control now keeps one structural identity while routing credentials back to selection.
3. The first credentials design also had a P2 duplicate demo action after the demo school had already been chosen. That redundant control was removed, content spacing was tightened, and both primary actions now remain visible without scrolling at the target viewport.
4. The final equal-density comparison shows complete progress chrome, readable Space Grotesk titles, clear selected/completed stage states, a concise selected-school summary, and separate working actions for continuing and connecting.

## Required Fidelity Surfaces

- Fonts and typography: both stage titles use the existing Space Grotesk Bold display token; native semantic styles provide clear supporting hierarchy without truncation.
- Spacing and layout rhythm: compact onboarding-specific spacing keeps each state above the fold while preserving the existing Gradely margins, card radii, and input sizes.
- Colors and visual tokens: the established Aurora background, grouped semantic surfaces, teal brand accent, segmented control, and primary gradient are retained.
- Image quality and asset fidelity: all visible symbols are crisp SF Symbols at native device scale; no raster placeholder, custom SVG, or approximate asset was introduced.
- Copy and content: selection copy only discusses finding a school; credential and Keychain guidance appears only after a school has been selected.
- Icons: the school, lock, stage, provider, help, password-visibility, and navigation symbols share one native icon family and consistent optical weight.
- Interaction and accessibility: provider switching, directory search, manual URL, demo selection, Continue, Change, Back, credentials, password visibility, Bakaláři login, EduPage two-factor, and child selection are functional. Stable identifiers and minimum target sizes are preserved.

## Verification

- Xcode project build: passed.
- Guided guest onboarding UI test: passed.
- Two-stage visual-reference UI test: passed.
- EduPage two-factor and child-selection onboarding UI test: passed.
- The visual-reference test asserts that credentials are absent during selection, school fields are absent during credentials, and Back returns to school selection.

final result: passed
