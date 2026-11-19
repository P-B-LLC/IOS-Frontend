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
  guards).
- `WorkoutStore.reloadWeek` downloads the entire history of schedules and
  workouts every time it needs just the current week, because the backend
  API has no date filter yet. Needs a backend change, not just a frontend fix.
  *The backend side is done (2026-10-10, repbase branch
  `for-you-video-security`): `GET /api/v1/schedules/?start=&end=`. What is
  left is here: copy the contract, regenerate the client, and pass the week.*
- Separate from this round of work: your last Xcode build surfaced 18
  pre-existing compiler warnings. 6 of them are real concurrency-safety
  issues that will become hard errors if the project moves to Swift 6
  language mode. Not touched in this pass.
