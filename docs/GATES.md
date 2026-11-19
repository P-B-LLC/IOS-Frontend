# Write-ordering gates

Four pieces of work that all answer one question: what happens when a write
and a read disagree about which came first, or when a reply never arrives.
They were four documents, written to be read once by whoever took the next
shift. That has happened, so this keeps the part that the code and tests
cannot tell you — what each one guarantees, and what nobody has verified —
and drops the narration of how each was built, which `git log` holds better.

Superseded: `SAVE_RECOVERY.md`, `PLANNER_COMPLETION_GATE.md`,
`WORKOUT_SAVE_GATE.md`, `FOOD_DAY_SYNC_GATE.md`. The backend keeps its own
`SAVE_RECOVERY.md` for the server side of the same feature.

---

## What each one guarantees

**Save recovery.** A create carries a durable operation key and the snapshot
it was first sent with, both persisted, so a retry after the app is killed is
recognisably the same request. The server keeps a receipt: the resource and
the response commit together, and a replay returns the first answer rather
than making a second row. Past the retention window the payload expires and
the key does not — the row becomes a compact 409, so a very late retry is
refused rather than duplicated.

**Workout writes.** Create and edit go as one atomic request rather than a
create followed by edits that can each fail alone. Finishing reports when the
session actually ended, not when the request got through. Set receipts last
until the set is unlogged.

**Planner completion.** Completion is serialised per server task id, not per
row copy. One completion-only PATCH with an explicit value, the confirmed
state held on failure rather than guessed, and reads started before or during
a write cannot apply over its result.

**Food day sync.** Reads carry an identity and an order, days carry a write
revision, and ensure-day counts as a write — it is a POST that can create
slots, and treating it as a read let a month response replace the day it had
just built.

## What none of them cover

- **Per-client serialisation, not cross-device ordering.** Two phones can
  still interleave in ways no client-side lock can see.
- **A timeout still means "unknown".** The server may have committed and lost
  the reply; that is what the keys are for, and it is a narrower promise than
  "no lost writes".
- **No device acceptance.** Nothing here has been exercised on a real phone
  with slow or dropping networking, an app killed mid-write, an account
  switched underneath a pending save, or a locked device's protected files.
  Every one of these was verified in tests and on a simulator only.
- **Restored-editor UX is unproven.** A draft offered back after a crash has
  never been seen by a person.

Device acceptance is part of the beta checklist in
[BETA_READINESS.md](BETA_READINESS.md), and needs hardware that needs an Apple
Developer membership.
