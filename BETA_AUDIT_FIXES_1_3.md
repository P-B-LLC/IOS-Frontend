# Beta audit fixes 1–3 — 2026-09-13

Implemented: atomic default gear switching and safe photo publication in
`repbase`; serialized social likes in this repository.

## Social likes

- One request per original post at a time, including its repost copies.
- The shared action button shows a spinner without changing layout and is
  disabled while pending. Unrelated posts remain interactive.
- Only confirmed like state/count change; no optimistic rollback and no full
  post replacement that could overwrite newer comments or captions.
- Account reset invalidates late success and failure responses.
- Confirmed values update Feed, Discover, open post details, and author lists.
- A failed/uncertain response leaves the confirmed UI intact. Retrying the same
  set-liked operation is safe; general stale feed reads remain a separate audit
  gate, not claimed fixed here.

## Verification

- Final backend suite: 308 tests ran, 305 passed, 3 PostgreSQL-only skipped.

- Native regression harness: 36 tests passed, including four deterministic
  held-response like tests: duplicate taps/undo, independent requests with
  reordered failure, late account success, and late account failure.
- Release simulator build passed on the Mac with signing disabled and
  `REPBASE_API_URL=https://ci.invalid/` (validation only, not a deployed server).
- Backend migration check passed; generated backend schema matches the committed
  contract. No client regeneration or API change was necessary.
- Backend failure tests cover default creation/editing, default-save rollback,
  original/thumbnail failures, cleanup retries, successful publication,
  serialization rollback, and interrupted-request cleanup.
- PostgreSQL concurrency tests are wired into backend CI but not executed on
  this Mac. Physical-device UI/VoiceOver testing remains outstanding.

Validation artifacts: Mac
`/Users/user299988/Documents/RytivoBetaValidation/audit-fixes.sj2HeA/`.

No live deployment or Git push was performed by this implementation pass.
Other audit gates remain open; this is not a whole-app beta approval.
