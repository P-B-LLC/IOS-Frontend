# Rytivo Home Screen widgets

## Active lifting session (new, native validation pending)

An Active Workout widget (medium/large) and a Lock Screen/Dynamic Island Live
Activity now share the current set. Weight controls adjust by 2.5 kg, reps by 1;
the kg label matches the current in-app lifting editor. Exact keyboard entry is
via Edit in app. The elapsed timer uses the original start date, not a tick loop.

Logging awaits the same existing WorkoutStore request used by the app. It never
unlogs a set. Pending writes, old rendered revisions, and another session's taps
are rejected. Successful saves advance to the first unfinished set in exercise
order; failed saves stay on that set. The last set offers Review & finish, not
automatic session termination. No APNs credentials or authentication tokens are
shared with the extension. LiveActivityIntent routes actions to the app process.

Lifecycle limitations: if the process was terminated and the authenticated
session is not restored, actions report that Rytivo must be opened. This is not
an independent offline extension save queue. Inactive data becomes stale after
an hour without an update, or eight hours after workout start; opening the app
refreshes it. Cardio sessions are not supported by these lifting controls. Live
Activities require system permission and an active app when first requested.

Required signed-device tests: adjust and log while foreground/background/locked;
confirm single server set after rapid double-tap; disconnect networking and retry;
edit values in the app then tap an old widget; finish/cancel/logout; force quit
then tap; restore session; check Dynamic Island and medium widget error layout.
Unit tests exercise set selection and decimal/rep controls, but do not replace
these integration checks. Use simulator signing enabled, not an unsigned build.

First version: My Day, Workout, Daily Nutrition, and Planner, in small and
medium sizes. Tap to open the corresponding app tab. These are read-only
summaries, not background task-completion or food-logging controls.

Planner now has Previous/Next App Intent buttons: small shows one item per page,
medium two, and the new large size seven. The range label includes tasks and
events; the completion count includes only completable tasks. Page state is
shared between planner widgets of the same size, separate across sizes, and
resets whenever a new snapshot is published. Old-rendering taps are ignored
after a snapshot change, logout, or midnight. Navigation does not write to the
backend or change completion. iOS still controls timeline reload timing.

Paging validation: check 0, 1, 2, 3 and 8 items; navigate both ends; remove items
while on the final page; check all sizes and rapid repeated taps. Boundary tests
are included in WidgetSnapshotTests. Native compilation and interaction testing
for the paging addition are pending Mac validation.

## Apple setup (required for signed device/TestFlight builds)

- Register App Group `group.com.pbllc.rytivo`.
- Enable that group on the main App ID `com.pbllc.rytivo`.
- Register extension App ID `com.pbllc.rytivo.widgets` and enable the same group.
- Refresh signing profiles for both targets. The project embeds the extension;
  building the existing app scheme builds both. No APNs key is used by widgets.
- HealthKit remains enabled only on the main app. Movement widgets are deferred;
  this extension never receives raw HealthKit data or authorization tokens.

## Data and behavior

The signed-in app writes a minimal, atomic, file-protected snapshot into the
shared group container after connecting its stores. Changes trigger WidgetKit
reload requests only when displayed data changes. The widget makes no network
requests. iOS controls when reloads actually appear; these are not live counters.

Unknown data stays unknown, rather than being displayed as zero. Every populated
widget shows its last snapshot update time. Yesterday's data expires at midnight.
Logout clears the snapshot and requests a reload; iOS may briefly retain its
previous rendered view. Account switching clears before new stores publish.
Widget contents are marked privacy-sensitive.

The snapshot is of app-store state, not a fresh background API read. Users must
open the app to synchronize changes made from other devices. Workout summaries
come from scheduled planner workout entries. No workout schedule means a rest/
planning state, not an invented workout. App-group setup failures result in the
open-app placeholder, not fallback storage in an unshared directory.

## Validation

`bash Scripts/test-account-safety.sh` includes WidgetSnapshotTests for corrupt
and cleared files, stale/future dates, date boundaries, missing versus empty
data, subtask serialization, and progress clamping.

Device checks still required: build the app and extension, add all four widgets
in both sizes, inspect light/dark mode and large text, log food, finish/reopen a
subtask, open each widget with the app terminated, switch accounts, sign out,
and cross midnight. Verify the fonts are Nunito Sans and the App Group is shared.

At implementation time native builds/tests could not be run because the Mac
SSH connection was closing during authentication. Do not treat this checklist
as a passed simulator or TestFlight test.
