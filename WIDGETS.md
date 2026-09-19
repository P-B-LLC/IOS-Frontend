# Rytivo Home Screen widgets

First version: My Day, Workout, Daily Nutrition, and Planner, in small and
medium sizes. Tap to open the corresponding app tab. These are read-only
summaries, not background task-completion or food-logging controls.

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
