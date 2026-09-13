# Beta audit gate 7 — rapid task completion

## Implemented flow

`PlannerStore` uses the production `PlannerCompletionCoordinator` for all task
completion changes. The coordinator is main-actor isolated and locks by integer
server task ID, not the UUID of a particular row copy.

1. Ignore redundant assignments and further taps while this task is pending.
2. Show a native pending indicator and disable this task's completion control in
   both calendar/day and overdue lists. Other tasks can save concurrently.
3. Send one existing completion-only PATCH with an explicit boolean value.
4. On an accepted response, update only completion (not stale title/schedule
   metadata), then emit the completion event. Day totals use confirmed state.
5. On failure, release the lock, retain the last confirmed display, and expose
   inline retry feedback. No optimistic rollback or automatic retry loop.

Connection epochs invalidate old success/failure callbacks, including lock
cleanup. Read tokens prevent GETs started before/during a completion write from
overwriting its result; a subsequent clean refresh remains authoritative for
other-device changes. Editing/deleting a pending task is also guarded by server
identity. An editor opened earlier preserves current completion when saving its
other fields.

This is per-connected-client serialization, not cross-device transactional
ordering. A transport timeout can still mean the server committed but its
response was lost. A retry assigns the same boolean rather than toggling on the
server; a fresh reload can reconcile the server value. No promise of zero network
failures is made.

## Regression coverage

`Tests/AccountSafety/PlannerCompletionTests.swift` tests the actual production
coordinator with held asynchronous responses:

- Rapid on/off through multiple copies of the same server task sends one request;
  undo is accepted after confirmation, with no extra completion celebration.
- Different tasks finish in reverse order; failure of one cannot roll back the other.
- Old-account success and failure cannot unlock or update a new pending request.
- Reads started before/during PATCH cannot undo confirmation; fresh reads work.
- Failed undo preserves confirmed state, emits no success, and can be retried.
- No-op assignments send no request and emit no celebration.

All asynchronous waits assert completion with a bounded timeout. These are not
timing sleeps or a device reproduction. The existing CI native-test step includes
these tests through `Scripts/test-account-safety.sh`.

## Validation

Mac validation workspace:
`/Users/user299988/Documents/RytivoBetaValidation/planner.7gYQpi`.
The final run passed all 25 native tests (six new); integrated Debug and Release
arm64 simulator builds passed. Results are recorded in `native-tests.log`,
`build.log`, and `release-build.log` there. No backend/contract change or production migration is
required for this gate. This work has not been pushed or deployed.

Physical-device acceptance remains part of the overall beta checklist: slow/
offline connection, check/uncheck repeatedly, verify spinner and inline recovery
in light/dark mode, and verify only confirmed transitions celebrate.
