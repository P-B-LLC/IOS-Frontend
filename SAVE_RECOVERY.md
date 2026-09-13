# Reliable saves and recovery — beta item 2

## Implemented

- Food, food picker, nutrition goals, recipe, planner task/event, and workout
  editors await saves and retain values on failure. Repeated submissions and
  interactive dismissal are disabled while saving. Food edits retain server IDs;
  completion celebrations follow confirmed writes.
- Food, recipe, planner, and new workout creates send stable UUID idempotency
  keys. Original submitted snapshots persist per account/backend before requests.
  Ambiguous failures replay that snapshot; later user edits apply to the confirmed
  resource rather than creating another one.
- Food/manual-entry, food-picker, recipe, planner, and workout editor drafts
  survive restart. New workout drafts use stable date/library contexts, not new
  random view IDs. Cancel retains the draft; successful saves clear it.
- Workout creation sends template, exercises, and initial schedule atomically.
  Editing sends an atomic exercise plan retaining existing relation IDs.
- Finishing a workout first persists an account/backend-scoped queue entry.
  Retry-safe route batches/end requests preserve the original finish time. One
  failure does not block other queued sessions. Logout preserves recovery;
  account deletion/session discard prevents replay.
- Active workouts checkpoint set state and route points (GPS writes throttled
  to five seconds, forced on background). Recovery checks server status and
  offers explicit GPS resumption without clearing restored points. Foreground
  and manual retry also retry reopening a checkpoint after network failure.
- Recovery uses atomic writes, iOS file protection, backup exclusion, account/
  origin isolation, and deletion tombstones. Corrupt pending snapshots are
  reported rather than overwritten by new requests.

## Contract and rollout

Deploy the backend changes and migration `0049_save_receipts` before distributing
this client. Backend `openapi.yaml` and iOS `API/openapi.yaml` match. Generated
Swift sources were regenerated on macOS using `Scripts/generate-api-client.sh`.
No generated Swift was hand edited. No push, deployment, production migration,
signing, or TestFlight distribution occurred in this batch.

## Verified 2026-09-12

- Backend: 278 tests ran, OK, two PostgreSQL-only skips (276 passed).
- Native account/navigation/recovery harness: 19 tests, zero failures, including
  actual storage tests for lost-response snapshots, relaunch, account/origin
  isolation, corrupt data, and deleted-account late writes.
- Generic simulator Debug build succeeded on Xcode 26.6.
- Simulator Release (arm64, unsigned) build succeeded. Its built Info.plist
  carries the supplied `https://ci.invalid/` test origin; this is not a deployed
  beta API or a signed-device test. Existing compiler warnings still need review.
- OpenAPI validation, migration drift, stable-ID and whitespace checks passed.
- Isolated Mac workspace/logs:
  `/Users/user299988/Documents/RytivoBetaValidation/build.JOpjBI`.
  The user's existing Mac checkout was not overwritten.

Storage tests do not exercise full SwiftUI lifecycle or repository HTTP transport.
Compilation and unit tests are not substitutes for device acceptance.

## Remaining gates — not a beta sign-off

1. The iOS client still uses create-then-start without durable idempotency. A lost
   response can leave an unconfirmed session. Backend commit `eccc2c3` now adds
   session/set create idempotency and replay-safe start, but iOS generated
   headers/client operation persistence still need integration. Set-log POSTs
   need lost-response reconciliation, including checkpoint restoration and
   intentional unlog/relog (which must receive a new operation key).
   Not every app write is retry-safe yet.
2. Execute PostgreSQL concurrency CI for first-create receipt locking and
   overlapping route/end retries. SQLite skips these tests. The hosted Mac's
   administrator-owned Homebrew directories prevent a PostgreSQL install;
   do not change shared directory ownership to bypass this.
3. Device/end-to-end acceptance: airplane mode at Finish; kill/relaunch after
   server commit but lost response; retry edited values; partial route uploads;
   account switch/deletion during requests; background/foreground; recovered
   GPS continuation; rapid task/set completion toggles.
4. Verify restored-editor UX, cancel/reopen, and a deliberate discard-draft
   option. Nutrition-goal and ingredient subeditor text is not independently
   checkpointed across process termination. No universal offline-save guarantee.
5. Verify light/dark, accessibility, protected files on a locked device, signed
   Release configuration, and the actual beta backend migration.

Keep each gate open until its specific acceptance evidence is recorded.

## Planner completion follow-up

Audit gate 7 now has server-ID pending locks, confirmed-only completion/events,
stale-read protection, and deterministic race tests. See
`PLANNER_COMPLETION_GATE.md` for the flow, coverage, and device acceptance scope.
