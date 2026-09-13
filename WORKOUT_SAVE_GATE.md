# Workout create/start and set-log recovery

## Implemented, 2026-09-13

- Generated session/set POST headers now include `Idempotency-Key`. Backend/iOS
  contracts were regenerated together; Swift was generated on the Mac.
- Starting persists the intended workout/day and original create request before
  network work. Lost create/start responses reuse the same session. Recovery
  resumes an interrupted start after relaunch, without automatically enabling GPS.
- A start receipt is consumed only after a durable active-session checkpoint or
  a confirmed terminal server state. A consumed marker protects the two-file
  cleanup against interruption. Rejected input can be corrected without a stuck
  intent; completed/deleted sessions do not get silently restarted.
- Set logging persists an operation UUID, original values and completion time.
  Lost replies replay that request. Once acknowledged, its resource ID remains
  available through a crash before the UI checkpoint. No new POST is needed.
- An uncertain retry confirms the original saved values. If the user changed
  fields meanwhile, the app shows those saved values and explicitly explains
  that they can unlog to edit; it does not silently pretend newer values saved.
- Unlog writes a deletion marker before DELETE. A lost reply/404 is safe to
  recover. The marker must be cleared before a relog gets a fresh UUID. Removing
  an unconfirmed set also resolves its earlier create before deleting the row.
- Restoring a session reconciles set IDs, values and logged status against the
  server. Confirmed receipts for rows that no longer exist are not replayed as
  phantom logged sets. Inputs are guarded during an in-flight set mutation.
- Storage remains account/backend scoped, protected and excluded from backup;
  deletion tombstones reject late writes. Set receipts remain until unlog or
  account deletion; they must not expire while an active-session retry can use them.

## Verification

- Seven new native tests exercise the production recovery flow with actual disk
  storage and simulated commit-then-lost-response callbacks: relaunch and exact
  replay, deletion/relog, corrected validation failure, interrupted start receipt
  consumption, account deletion during a response, and delayed responses trying
  to resurrect a consumed receipt or erase a newer relog receipt.
- All 32 native regression tests passed.
- All 27 focused backend recovery tests passed. Full backend suite: 288 tests
  ran, OK; two PostgreSQL-only skips (286 passed).
- Debug and final Release arm64 simulator builds passed (unsigned). Mac logs:
  `/Users/user299988/Documents/RytivoBetaValidation/workout.VCEt1N`.
- Schema parity, stable-ID and whitespace checks passed.

This tests the production persistence/operation flow and server retry behavior
separately. It is not a claim that signed-device lifecycle/transport tests ran.
Before beta distribution, validate on a device against the deployed backend:
kill after create/start/set commit; reconnect; unlog with lost DELETE reply;
relog with different values; remove an unconfirmed set; switch/delete accounts;
restore GPS explicitly. PostgreSQL concurrency and actual beta deployment remain
separate gates. These writes require the backend's session/set idempotency and
replay-safe start changes, not an older deployment.
