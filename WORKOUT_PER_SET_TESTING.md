# Durable per-set planning — testing only

Branches: iOS `work/testflight-fixes-2026-10-27`; backend
`work/testflight-calendar-sync-2026-10-28`. Main, live backend and TestFlight
are unchanged. This is not a release approval.

## Behavior

- Review workout has independent reps/weight inputs for each set, set-type
  selection, removal, Add set and an explicit Apply first set targets to all.
  Inputs are keyed by exercise and stable set ID, not screen position.
- The [approved review design](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=422-16351)
  is used with the user's later override: no kg/lb switch or default checkbox
  during planning. Labels use the account unit; active exercise choices remain
  independent. Canonical stored weights are kilograms.
- Reps are optional or 1–1000; weights are optional or 0–99999.99 kg with two
  decimal places. Up to 50 sets per exercise. Zero weight is valid; invalid
  input is shown and cannot be saved. Copy-first is explicit, never automatic.
- Templates store rows; a started session receives an immutable snapshot.
  Planned targets are distinct from actual logged results. Reordering/removing
  rows, resume and explicit save-for-next-time retain target identity. Duplicated
  plans receive fresh local identities while preserving target values.
- Authenticated capability detection precedes catalog/template writes. An old
  backend cannot silently ignore these fields: the draft remains available with
  an update-required message. Readback verifies rows and values after saving.
- Legacy templates/checkpoints are compatible. Unknown historical targets are
  not fabricated from actual workout history.

## Contract and persistence

Backend migration `0093_workout_planned_sets` adds template rows and session
snapshot/provenance fields. `API/openapi.yaml` is copied from the backend's
generated contract; generated Swift comes only from the generator workflow.
Template writes advertise `planned_sets_version: 1` after the authenticated
`workouts/capabilities/` check. Backend mutation and snapshot operations lock the
parent template and reject ambiguous destructive writes by older clients.

## Verification

- Focused backend suite initially passed 242 tests, with five PostgreSQL-only
  skips locally. Schema validation, migration drift and Django checks passed.
- Added domain/contract/recovery regressions in `WorkoutPlannedSetTests`, plus
  updated unit-scope wiring guards. Run `bash Scripts/test-account-safety.sh`
  on Mac. Test registration is explicit and checked by the runner.
- Native `WorkoutFlowUITests` includes target editing, add/remove, copy-first
  and back/review persistence. Existing reorder and active-unit checks remain
  required; failures are not suppressed. Fixtures validate UI behavior only.
- Full current-head Mac builds and PostgreSQL tests run through GitHub CI.
  Consult the exact head/run result, not historical branch results. The prior
  `d2ff53f` candidate had two genuine native drag-position assertion failures,
  despite passing both builds and 525 regression tests.
- Follow [WORKOUT_LOCAL_TESTING.md](WORKOUT_LOCAL_TESTING.md) to verify real
  save/reopen/restart/start/log behavior against an isolated persistent backend.
  Test two different targets, warmups, empty targets, zero-weight sets, both
  appearances, larger text, per-exercise units and cancellation/recovery.

Do not point this test at the live API expecting new persistence. The live server
is not deployed by this work. No watch integration or automatic target progression
is added.

## Recorded validation — November 12, 2026

- Backend `646fe55`: [full CI passed](https://github.com/P-B-LLC/repbase/actions/runs/43342090609).
  Both 1,710-test suites (SQLite/PostgreSQL), schema freshness, production
  settings and dependency audit passed, including the new lock-order race.
- iOS `2a8ad2f`: [full CI evidence](https://github.com/P-B-LLC/IOS-Frontend/actions/runs/43341914649).
  Debug and Release builds, generated-client consistency, localization and
  all 551 regression tests passed. Native results were **3/5**, not a full pass:
  exercise-only units, builder scope and short whole-card drag/target retention
  passed; per-set editing and edge-autoscroll cases failed.
- The per-set test's caret-based deletion inserted `612` instead of replacing
  `12` with `6`. Follow-up uses the actual Select All menu and immediately
  asserts the exact replacement. Edge screenshots show the drag overshooting
  into the nonmovable catalog; the follow-up bounds its hold while retaining
  the original beyond-initial-visible-position assertion. These are test
  interaction changes, not evidence of an app fix or of a passing rerun.
- Light/dark review previews were inspected. The large-text initial preview
  does not show the full table; a scrolled large-text manual check remains.
  Current-head native rerun and real local save/reopen/start checks are still
  required. Do not promote this branch based only on successful compilation.
