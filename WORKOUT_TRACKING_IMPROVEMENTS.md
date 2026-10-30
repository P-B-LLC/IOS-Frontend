# Workout tracking, saved workouts and follow status — October 2026

Branch: `work/testflight-fixes-2026-10-27` (uncommitted when written). Backend
counterpart: `repbase` branch `work/testflight-calendar-sync-2026-10-28`
(migration `0082_set_type_and_planned_set_structure`). Not merged, tagged or
uploaded.

## What changed

- **Live lifting screen** (`Views/Workouts/Session/`): every exercise is a card
  with a SET · PREVIOUS · weight · REPS · ✓ table. The current set is marked,
  logged rows are tinted, completed exercises collapse, and the header shows
  time, sets, exercises, volume and a kg | lb switch. Checking an empty row logs
  the hint shown in it (target, else last time); untouched fields never pretend
  to be today's numbers. Keyboard toolbar has previous/next/done.
- **Set kinds**: normal, warm-up (W), drop (D), failure (F). Chosen from the set
  number in a session or in a plan. Warm-ups are not working sets: unnumbered,
  left out of volume, and excluded by the backend from records, progress and
  highlights. A drop set never starts a rest before it. Hints match by kind and
  place, so an added warm-up does not shift them.
- **Rest timer** (`Services/RestTimer.swift`): an end date, not a counter, kept
  in the checkpointed session, so screens, relaunches and the Lock Screen all read
  the same value. Start/pause/resume/±15/skip/restart. Default rest, auto-start
  and alerts in Settings > Workouts; per-exercise rest in the session and the
  plan. A superset rests after the last exercise of each round. A local
  notification fires at the end while the app is not in front.
- **Lock Screen / Dynamic Island**: new `RytivoWorkoutActivity` widget extension
  (`com.pbllc.rytivo.WorkoutActivity`). Shows exercise, set, target, last time,
  progress and the rest countdown (drawn from dates, so it runs while the app is
  suspended; past its stale date it reads "Rest is over"). Buttons: complete set,
  pause/resume, +15 s, skip — `LiveActivityIntent`s that run in the app process.
- **Reshaping a session**: add (catalog or new name), remove (confirmed when sets
  are logged), reorder (sheet), add/delete any set, change kinds, rest, superset.
  At Finish, only if the shape changed, the app asks whether to update the saved
  workout or keep the change to today. Weights and reps never trigger the
  question.
- **Units**: account `unit_preference` is the default (Settings > Workouts); the
  kg | lb switch changes display everywhere until relaunch. Exact factor
  0.45359237; pounds shown to 0.1 lb so typed pounds read back unchanged.
- **Plan review**: compact cards with no arrows, set-kind chips, rest, superset,
  optional target reps/weight. Reorder opens a list of the exercises to drag by
  their handles (the system list drag; VoiceOver also has Move up/down on each
  card). In-place drag-and-drop over the cards was tried and dropped: SwiftUI's
  general drag gives no callback when a drag is abandoned, and in testing it
  left the app stuck mid-drag.
- **Saved workouts**: search, recent/A–Z, exercise preview, sets, estimated time,
  last done; Start, Add to a day, Edit, Duplicate, Delete (now confirmed; its
  accessibility label was previously "Add").
- **Explore exercises**: one shared catalogue for the builder and the session,
  the account's own exercises first, server search plus local filtering, and new
  exercises offered right after the save that created them. A name already in
  use picks the existing exercise.
- **Follow status**: the button shows only your side (Follow, Follow back,
  Request to follow, Requested, Following ⌄); "Follows you" / "You follow each
  other" is a separate label. Unfollowing and withdrawing a request are
  confirmed; taps are optimistic and roll back on failure. Same control on
  profiles, private profiles, search and suggestions.

## Backend contract (additive)

`SetEntry.set_type`; `WorkoutExercise.rest_seconds / superset_group / set_types`;
`POST /api/v1/sessions/{id}/reorder/`; `PublicRepbaseUser.follows_viewer`;
`WorkoutTemplate.last_performed_at`; `GET /api/v1/exercises/?search=&mine=`.
Every new response field is optional, so this app degrades gracefully against
the old backend (no kinds, no "Follows you", no last-done dates, local-only
reorder) and old apps keep working against the new one. Deploy the backend and
run its migration before relying on the new behaviour.

## End-to-end UI tests

`RytivoUITests` drives the real app against a real throwaway backend:

```bash
bash Scripts/run-e2e-ui-tests.sh            # creates and deletes its own simulator
```

It starts `../repbase` under `config.test_e2e` on a temporary SQLite file,
seeds it (`Scripts/e2e-seed.py`), builds the app against it and runs five
flows: a full lifting session (set kinds, rest controls, kg/lb, add/delete
set, add/remove/reorder exercise, rest change, Finish with the plan
question); saved workouts (duplicate, confirmed delete, edit + reorder,
start); Explore exercises (reuse vs create, offered again next time);
following (Follow back, mutual, confirmed unfollow); and workout settings.
The tests skip unless `TEST_RUNNER_RYTIVO_E2E=1` is set, which the script
does, so they never run against a real account. On 2026-10-29 all five
passed against this branch's backend and against the backend as it was
before these changes (a stand-in for the deployed server).

## Device checks still required

The simulator cannot lock the screen here, so on a device: start a workout,
lock the phone, confirm the activity shows and its countdown runs; use each
button locked and unlocked; let a rest end with the phone locked (notification
and "Rest is over"); kill the app mid-rest and tap a Lock Screen button; check
the Dynamic Island compact/expanded views. Signing for the extension needs the
new bundle ID registered (automatic signing does this on the first archive).

# Activities, exercise library, effort, Lock Screen rest, discard — 29 October 2026 (second pass)

Same branches, still uncommitted. Backend migrations `0083`–`0085` (see below).

## What changed

- **51 activities** (`Models/WorkoutActivity.swift`, backend `core/activities.py`):
  strength (weightlifting, calisthenics, CrossFit, circuit, functional, HIIT),
  cardio (running, jogging, sprinting, trail running, walking, cycling, indoor
  cycling, mountain biking, pool and open-water swimming, rowing, indoor rowing,
  elliptical, stairs, jump rope), racket (tennis, padel, badminton, table
  tennis, squash, pickleball), team (soccer, American football, basketball,
  volleyball, rugby, hockey, baseball, handball, cricket), combat (boxing,
  kickboxing, martial arts), mind & body (yoga, pilates, stretching, dance),
  outdoors (hiking, climbing, skiing, snowboarding, surfing, paddling, golf),
  other. The builder shows ten common ones and a searchable sheet for the rest.
- **Each activity asks only what applies.** Three profiles: *strength* (the
  existing exercises → sets builder and live session), *distance* (time,
  distance, pace/speed worked out, GPS only for outdoor ones), *session* (time
  and effort). On top, optional per-activity questions: match / training /
  casual for racket and team sports; format, rounds, extra reps and movements
  for CrossFit; rounds for HIIT, circuits and boxing; style for yoga, pilates,
  martial arts and climbing; routes for climbing; sprints for sprinting;
  elevation gain for hikes, trail runs and rides; pool length for pool swims.
  Distance is asked for distance activities and optionally for soccer, rugby,
  sprinting, elliptical, skiing and "other". Switching activity keeps time,
  effort, calories and notes and drops everything that no longer applies.
- **Logging after the fact.** For anything that is not strength, the builder's
  second step is "Log a finished session" (default) or "Plan for later". Only
  the time is required. A planned activity's day card also offers "Already
  done? Log it". Logging is offered only for today or earlier, and the finish
  time is limited to that day, so the session is filed under the day it
  happened. One request (`POST /api/v1/sessions/log/`) finds or makes the
  workout of that name, schedules it on the day, records a completed session
  (`is_manual_entry`), and ticks the day's planner task. The idempotency key is
  derived from the content, so a retry after a lost answer never logs twice.
- **Effort chart** (`Views/Workouts/EffortChart.swift`): 0–100, five columns
  rising like the reference drawing, filled in the app's caramel up to the value
  and white with a dark outline above it (surface and primary-text tokens, so
  dark mode stays legible). Tap or drag; the value, band and a one-line
  description update live; "Clear" makes it unrated again. VoiceOver adjusts in
  steps of 5. Bands and words are Rytivo's own (Very easy, Easy, Moderate, Hard,
  All out), not Borg's licensed scale wording.
- **After a live session**, "How did it feel?" asks effort (every activity,
  lifting included), plus details and calories for non-strength activities, and
  distance only for indoor distance activities where nothing measured it
  (`PATCH /api/v1/sessions/{id}/`).
- **History.** The day's completed card shows time, distance (labelled
  *Measured* for GPS/Health, *Your entry* when typed), effort, calories (always
  *Your estimate*), details, notes and "Logged after the session". Training now
  has a **Recent activity** list (last 8 sessions, every kind) with a detail
  sheet. Totals, streaks and "last done" count a timed activity as trained by
  its duration or distance; a strength session still needs a logged set.
- **Exercise library**: one JSON file, `repbase/core/data/exercise_library.json`,
  built by `repbase/Scripts/exercise_library/` (base: free-exercise-db,
  Unlicense, plus a curated Rytivo supplement), copied into the app by
  `Scripts/sync-exercise-library.sh`. The app searches it offline (name and
  aliases, case/accent/punctuation-insensitive, ranked exact > prefix > rest),
  filters by muscle region chips and a Filters sheet (equipment, movement
  pattern, exercise type, training style), and shows each exercise's muscles,
  equipment, level, steps and variations. The account's own exercises come
  first; one whose name or alias matches a library entry is shown once, as
  theirs. The backend seeds the same file as shared exercises (upsert by slug,
  adopting an unslugged shared row with the same name, never touching custom
  ones, never deleting), so a library choice resolves to the shared row by name
  when saved — or, against an older server, becomes the account's own exercise
  with its muscle group.
- **Lock Screen rest countdown.** The "1:--" was the Always-On Lock Screen: when
  it dims, iOS stops redrawing every second and shows timers with more than a
  minute left as minutes and dashes (Apple's Timer does the same; there is no
  API to turn it off). While the Lock Screen is dimmed (`isLuminanceReduced`)
  the activity now shows **"Rest ends at 9:41"**, which is exact without
  redrawing; awake, it counts down as before. The rest itself was already an end
  date (unit tests now cover 30 s – 10 min rests read at arbitrary later times,
  finishing exactly once).
- **Deleting a started workout.** The store's discard existed but the lifting
  session never offered it. Now: a red **Discard workout** at the end of the
  session (as in the reference), **Discard workout** in the "Finish with
  unfinished sets?" prompt and in the "Nothing logged yet" notice, and the
  run/ride close button — all through one alert, *Delete this workout?* with
  **Cancel** / **Delete Workout**. Deleting removes the server session (its
  exercises and sets cascade), the local checkpoint, pending-save recovery, the
  route, the rest notification and the Live Activity. A failure is reported and
  the session stays open with nothing lost; a session the server no longer has
  counts as deleted, so nothing can stay stuck active.

## Contract (additive, every new response field optional)

- `WorkoutTemplate.activity`, `WorkoutSession.activity` (read-only),
  `PostWorkout.activity` — plain strings, not an enum, so a later activity never
  breaks an older build (it reads as "Other activity"). `workout_type` keeps its
  four values as the activity's *family*, which is all an older build reads:
  tennis arrives there as lifting with no exercises.
- Session: `perceived_effort` (0–100), `manual_calories_kcal`,
  `manual_distance_km` (also fills `recorded_distance_km` when nothing measured
  a distance), `notes`, `activity_details` (validated per activity), and
  `is_manual_entry`. The first five are writable by PATCH.
- `POST /api/v1/sessions/log/` (`ActivityLogRequest`, `Idempotency-Key`).
- Exercise: `slug`, `aliases`, `category`, `equipment`, `movement_pattern`,
  `level`, `mechanic`, `force`, `family`, `primary_muscles`,
  `secondary_muscles`, `disciplines`, `instructions`; list filters
  `?equipment=&category=&pattern=&muscle=`; `?search=` matches aliases;
  `?name=` prefers the caller's own exercise.
- Migrations: `0083_activity_tracking_and_exercise_library` (columns),
  `0084_backfill_activity_and_search_text` (activity from `workout_type` for
  every existing workout and post), `0085_sync_exercise_library` (loads the
  library if the file is present). The sync adopts a shared exercise from
  before the library when its name is the entry's name or one of its aliases
  (the old "Lateral Raise" becomes "Lateral Raise (Dumbbell)", keeping its
  history) and creates a row only when nothing matches. After deploying, run
  `python manage.py sync_exercise_library` whenever the library file changes;
  the migration only runs once.

## Tests (29 October 2026, all green)

- Backend: `python manage.py test core`: 1,436 tests pass (24 skipped), including
  94 in `core/test_activity_tracking.py`. `makemigrations --check` is clean,
  and `openapi.yaml` parses and matches the app's copy.
- App unit tests: `bash Scripts/test-account-safety.sh`: 262 tests, 0 failures,
  including `WorkoutActivityTests` (19) and `ExerciseLibraryTests` (7).
- End to end: `bash Scripts/run-e2e-ui-tests.sh`: 8 of 8 pass. They cover
  discarding a started workout, a lifting session, saved workouts, exploring
  exercises, following, workout settings, logging tennis with the effort
  chart, and library search and filters.
- Fixed along the way so the suites run clean:
  - The library sync adopts old shared rows by alias, so it no longer creates
    duplicates.
  - The app links library picks to those rows.
  - `FoodPortionMeasurement` accepts the Arabic decimal mark (٫).
  - Seven food strings no longer used since 86a4ca0 were removed from the
    catalog.
  - The app name is marked do-not-translate.
  - The E2E script refuses a busy port.

## Known limits

- Exercise names, aliases and instructions are English (they are data, like
  server exercise names); muscle, equipment, pattern and category labels are
  translated. No exercise images yet.
- The rest-over notification uses the normal interruption level: Time Sensitive
  needs the `com.apple.developer.usernotifications.time-sensitive` entitlement
  and App ID capability, which signing here cannot add without a device.
- Apple Health import still maps only run/ride/swim/lifting.
- Older app builds see new activities by family only (tennis as a lifting
  workout without exercises).
