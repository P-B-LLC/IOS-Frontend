# Performance Fix: Image Caching + Launch-Time Font Scan

**Status:** Done, verified building and running in Xcode
**Date:** 2026-10-09
**Area:** iOS app

## Why

Four avatar views were using SwiftUI's plain `AsyncImage`, which
re-downloads and re-decodes images every time the view rebuilds. The app
already has its own `RemoteImage` component built specifically to avoid
that (it caches both the decoded image and the raw data, and decodes off
the main thread) — these 4 spots just weren't using it.

Separately, the app was scanning its entire bundle for font files on every
launch, even when it had already found all 3 fonts it needed through
faster, targeted lookups.

## What Was Changed

- Swapped 4 avatar views from `AsyncImage` to `RemoteImage`:
  - `SocialFeedView.swift` (feed avatars)
  - `PostDetailView.swift` (comment avatars)
  - `PostModerationViews.swift` (blocked accounts list avatars)
  - `SocialProfileView.swift` (profile avatar)
  - Same visual appearance and sizing — only the underlying loading
    mechanism changed.
- `CommunityTypography.swift` — the full bundle font scan now only runs if
  the quick targeted lookup didn't already find all 3 fonts, instead of
  always running both.
- **Unrelated bug fix found along the way:** `API/GeneratedSources/Client.swift`
  had a stray typo (`init(kk` instead of `init(`) that was breaking the API
  client's build entirely. This was not something introduced by this work —
  it was an uncommitted local change already sitting in the file. Removed it.

## Verification

- Could not run a full Xcode build from this session — the environment only
  had Command Line Tools, not full Xcode, installed at the time.
- Verified the `RemoteImage` usage pattern by hand against an existing,
  already-working call site in the codebase, and with a small standalone
  Swift check to confirm the exact function-call syntax compiles.
- Confirmed in Xcode (by you) that the typo fix resolved the build-breaking
  error, and that the app builds and runs correctly end-to-end with all of
  these changes in place.

## Needs To Be Changed / Improved

- 8 data stores (workout, social, food tracking, planner, etc.) connect one
  after another after sign-in instead of in parallel, which slows down
  time-to-interactive after login. Not fixed here — needs care, since some
  stores depend on others finishing first (callback ordering, token-race
  guards). *Fixed 2026-10-15: see the last entry.*
- `WorkoutStore.reloadWeek` downloads the entire history of schedules and
  workouts every time it needs just the current week, because the backend
  API has no date filter yet. Needs a backend change, not just a frontend fix.
  *The backend side is done (2026-10-10, repbase branch
  `for-you-video-security`): `GET /api/v1/schedules/?start=&end=`. What is
  left is here: copy the contract, regenerate the client, and pass the week.*
  *Fixed 2026-10-15: see the last entry.*
- Separate from this round of work: your last Xcode build surfaced 18
  pre-existing compiler warnings. 6 of them are real concurrency-safety
  issues that will become hard errors if the project moves to Swift 6
  language mode. Not touched in this pass.

---

# Performance: Stores Load Side by Side, the Week Reads Only the Week

**Status:** Done, not yet committed (branch `perf/app-wide-optimization`)
**Date:** 2026-10-15
**Area:** iOS app, after sign-in

## Why

Measured on the iPhone 17 simulator against a local backend holding an account
with a year of history, through a proxy adding 100 ms to every round trip (a
phone on a mobile network). From the moment the session is restored to every
store holding its data took about 2.9 s, for two reasons:

- **The eight stores connected one after another.** The last tab's data
  waited for every other tab's round trips first.
- **The week read every schedule the account had ever had**, fifty a page and
  one page after another, to draw seven days: seven sequential requests at a
  year of training, one more for every fifty days after.

## What Was Changed

- `IOS_FrontendApp.swift`: the profile store connects first, alone, because it
  is where the phone's time zone reaches the server, and the server works the
  other stores' days out in it. The rest then connect side by side. Workouts
  and the planner stay one after the other, in that order, because a new week
  of workouts is copied into the planner as it arrives. Each store already
  discards an answer that lands after a sign-out (its connection generation).
- `WorkoutAPIRepository.loadWeek` reads the schedules of the week on screen
  (`start`/`end`), and saving a workout checks only the day it is planned on.
- `APIConfiguration.rangePageSize`: the planner, meals, schedules and a
  session's sets ask for up to 200 rows a page (the backend's new optional
  `page_size`; a backend without it ignores it and pages at fifty).
- `API/openapi.yaml` and `API/GeneratedSources`: the backend's additive
  `page_size`, regenerated with `Scripts/generate-api-client.sh`. Regenerating
  from the previous contract first reproduced the committed sources exactly,
  so the diff is the parameter alone.

The backend change that goes with this matters: on SQLite, the stores' first
writes arriving together (planning the week, the planner's repeats, today's
meals, steps) failed one of them with "database is locked" until the backend
opened transactions `IMMEDIATE` (repbase, same branch). Deploy the backend
first, as usual.

## Verification

Session restored to every store connected, median of 4 runs, alternating:

| | Stores connected | Startup work finished |
| --- | --- | --- |
| Before | 2,996 ms (2,875-3,184) | 3,117-3,444 ms |
| After | 968 ms (941-990) | 1,173-1,243 ms |

- Requests at launch, first measured run: 57 before, 50 after. Seven
  `GET /schedules/` became one; the meals window (22 days, 88 meals) is one
  page instead of two.
- `xcodebuild` (simulator) builds clean from scratch, against the pinned
  package versions, with the same warnings as before.
- `bash Scripts/test-account-safety.sh`: 87 tests pass.
- Measured with a DEBUG-only probe in a copy of the app (a token from the
  environment, a timestamp printed when the stores are connected, the
  HealthKit sheet skipped because nothing can tap it). The probe is not in the
  repository. Nothing was tap-tested on a device.

## Needs To Be Changed / Improved

- The longest chain left is workouts then the planner, about seven round trips
  (plan the week; read it; restore the active session; copy workouts into the
  planner; read the month; read what is overdue and what is coming up).
