# Food day refresh ordering — audit item 4

Implemented 2026-09-13. Scope: stale food reads replacing newer confirmed day
contents. This does not declare the whole app beta-ready.

## Flow

- FoodDaySyncCoordinator assigns read IDs, read order and per-day write revisions.
  Reads started before or during a write cannot replace that day's state after
  either success or failure. A later clean read remains authoritative, including
  changes or deletions made on another device.
- Initial load, month reads and ensure-day responses use the same acceptance
  rules. A range response merges untouched days while rejecting conflicted days;
  omitted days clear old content only when the read is safe to apply.
- Day requests share an in-flight Task. Starting a write invalidates/cancels its
  older day fetch. Request identity prevents that old task from deleting a newer
  in-flight request when it finishes.
- A day requested during a write is queued once and fetched after the write
  ends. Recipe/plan refreshes use the same shared fetch. Month reads coalesce per
  month; loading state stays active until all pending month requests finish.
- Food creation/editing, meal rename/add/delete, food deletion, copied days and
  all recipe/plan target days participate in write protection. Recipe application
  also honors the existing save lock and deduplicates its requested dates.
- Connection reset invalidates old reads/writes, cancels shared day tasks, clears
  month-read state and prevents late callbacks from mutating a newer account.
- Only existing confirmed write paths create celebrations. A refresh never
  emits or replays a meal-log event.

## Verification

`bash Scripts/test-account-safety.sh`: 46 tests passed, including 10 new tests
using the production coordinator. They explicitly order old reads, writes and
newer reads without relying on network timing or sleeps:

1. An old day response cannot undo a confirmed food save.
2. A month accepts unaffected dates while protecting a changed date.
3. Reads overlapping a failed write are rejected; a later read can recover.
4. Initial load cannot overwrite a newer accepted day read.
5. Delayed month content cannot resurrect deleted meals.
6. Recipe protection covers every target date; subsequent reads remain valid.
7. Duplicate requests coalesce and completion/failure releases their slots.
8. Old completions cannot release a post-save refresh's slot.
9. Account reset invalidates late reads and writes.
10. Month loading stays active until every pending month finishes.

Validation workspace on the Mac:
`/Users/user299988/Documents/RytivoBetaValidation/food-sync.aHq2hV`.

Release arm64 simulator build: **BUILD SUCCEEDED**, signing disabled, validation
API URL `https://ci.invalid/` (not a production deployment). The stable-ID check
also passed for all nine UUID-identified models. Whitespace checks passed.

No backend endpoint, generated client or schema change. The tests exercise the
ordering component, not physical-device UI or full store-to-server integration.
Device checks remain: log/edit/delete with delayed networking, apply recipes
across dates, switch months rapidly and sign out during a fetch. General social
feed races, recipe-library/goal refresh ordering and other audit items are not
claimed fixed by this change.

Operational note: these are read-order safeguards, not a general offline write
queue. A network save failure is still shown honestly and can be retried through
the existing save workflow.
