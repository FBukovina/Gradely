# Personal school planner

Open Planner from the checklist button in the timetable toolbar. A dated timetable day has a “Plan this day” action, and lesson details offer “Add to Planner”. The existing tabs and weekly/permanent picker remain in place.

## Architecture

`PlannerStore` is an observable, main-actor store shared across live app windows. `AppEnvironment` supplies an isolated in-memory store and a disabled Calendar adapter to previews and mock UI tests. `PlannerPersistence` uses the existing atomic JSON and complete-file-protection convention under Application Support/Gradely/personal-planner.json. It is personal data, not a school cache: cache clearing, logout and changing schools do not delete it. It is local to the installation, including across school-account switches; Gradey does not upload it or use CloudKit.

`PlannerItem` contains editable content, item type, optional subject/lesson references, optional linked day and due time, completion, timestamps, a saved time zone and per-item Calendar state. Subject IDs retain provider whitespace and are scoped using the existing `SchoolDataScope`. Lesson matching uses account, day, hour, subject ID and sorted group IDs, so reordering timetable atoms or changing rooms/teachers does not attach a note to another lesson. No full provider objects are copied into planner storage.

Unreadable storage is kept intact and editing is blocked until it can be loaded. Local save failures do not mutate Calendar. Calendar failures leave the locally saved item visible and a retry action available. Disabling or deleting an item after permission denial clears the unattempted export without requesting cleanup access. Deleted items with unfinished Calendar cleanup retain a minimal tombstone until removal succeeds.

## Next lesson

`PlannerLessonResolver` reuses `SchoolRepository.loadTimetable`, `TimetableCache`, `TimetableMapper` and the shared timetable clock/date helpers. It first searches the linked weekly timetable, then at most four following weeks. It selects the earliest strictly later start for the exact subject ID and a compatible student group, skipping cancelled lessons, non-school days and invalid times. Network failures can use the existing cached week; an unavailable earlier week stops the search instead of choosing an unverified later occurrence. An account change or cancellation aborts the operation.

The resulting due date has a time. No result leaves the existing due date unchanged and displays a localized explanation. Permanent timetable lessons retain context but have no invented date or next occurrence; the user chooses a due date. Undated items and missing subject IDs also remain supported without a next-lesson guess. Future-week lookups suppress widget/watch publication so they do not replace the current timetable summary.

## Calendar export

`PlannerCalendarService` contains all EventKit calls. It requests full access only for explicit Calendar work because updating and removing existing events require fetching them; write-only access is insufficient for that lifecycle. See [Apple’s EventKit access documentation](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)).

The service creates or reuses a writable “Gradey” calendar on an available calendar source. Items without a usable source or permission stay local with pending work. `PlannerCalendarEventData` maps the subject, type, user title and notes to an event; a timed due date wins over lesson timing, and date-only items are all-day events. All-day ends use the next calendar day, including daylight-saving transitions. Completed items update the event title.

Gradey persists the event identifier and an ownership URL. Edits update the owned event; disabling export or deleting an item removes it. Missing events are harmless on removal and are recreated on the next Gradey edit when export is still enabled. Known date ranges and the ownership marker recover an interrupted identifier save without importing Calendar edits. Pending work is retried on activation only if access is already authorized, or through the explicit retry action. EventKit may sync the exported event through its calendar account; planner storage itself has no cloud synchronization.

No Bakaláři/EduPage write API, backend change, Calendar import or bidirectional synchronization is introduced.

## File inventory

Created:

- Gradely/Models/PlannerModels.swift
- Gradely/Stores/PlannerPersistence.swift
- Gradely/Stores/PlannerStore.swift
- Gradely/Services/PlannerCalendarService.swift
- Gradely/Support/PlannerCalendarEventData.swift
- Gradely/Support/PlannerLessonResolver.swift
- Gradely/Views/PlannerView.swift
- Gradely/Views/PlannerItemEditorView.swift
- GradelyTests/PlannerTests.swift
- GradelyUITests/PlannerUITests.swift
- Docs/Planner.md

Modified:

- Gradely/ContentView.swift and Gradely/Support/AppEnvironment.swift: store ownership, dependency injection and activation.
- Gradely/Models/TimetableModels.swift and Gradely/Support/TimetableMapper.swift: preserve provider subject/group IDs.
- Gradely/Services/BakalariRepository.swift: optional suppression of widget/watch publication during planner lookups; existing call behavior stays the default.
- Gradely/Support/DateFormatting.swift and Gradely/Support/TimetableTodaySummary.swift: shared validated lesson-time parsing.
- Gradely/ViewModels/TimetableViewModel.swift and Gradely/Views/TimetableView.swift: scoped links, day/lesson entry points, overview navigation and quiet incomplete-item indicators.
- Gradely/Resources/Localizable.xcstrings and Gradely/InfoPlist.xcstrings: all four existing locales and Calendar permission copy.
- Gradely-Info.plist, GradelyMac/GradelyMac-Info.plist and GradelyMac/GradelyMac.entitlements: EventKit privacy configuration on both app targets.

## Validation and remaining device QA

Validation is performed headlessly from a byte-for-byte source mirror because Xcode’s coordinated read of the iCloud checkout stalled before dependency resolution. No project configuration workaround is required in the repository.

Final verification on 6 September 2026:

- iOS Simulator Debug build and 48 unit tests in six suites passed.
- Four native UI tests passed: day creation/edit/completion/deletion; lesson context/next due date/indicator; week navigation; weekly/permanent switching.
- macOS Debug build passed.
- Source-mirror hashes match; diff whitespace checks, localization catalogs and both targets’ Calendar permission configuration passed inspection.
- Result bundle: `/tmp/gradey-planner-acceptance.xcresult`; macOS build log: `/tmp/gradey-planner-mac-acceptance.log`.

The automated tests cover subject/group matching, cancellation/holiday handling, week-boundary and offline lookup, missing data and account changes, timed/all-day/DST mapping, persistence across reopening, corruption/write failures, Calendar denial and retry, missing events, editing, disabling export, deletion and interrupted identifier persistence. Native UI coverage exercises planner workflows alongside the existing timetable navigation tests.

Real-device EventKit authorization and calendar-account CRUD remain manual release QA. The automated Calendar lifecycle tests use an injected adapter and do not validate a real Calendar account. A provider that changes both an event identifier and its date beyond the saved recovery range may leave an old exported event requiring manual cleanup. Removing an event’s Gradey ownership marker also prevents Gradey from treating it as its own.
