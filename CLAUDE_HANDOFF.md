# Repbase iOS — Work History and Claude Handoff

Last updated: August 16, 2026 (planner, then the profile and gyms)

This supersedes the previous handoff, which described the project at `ad1df5b`.
Everything in that document still worth keeping has been folded in here.

| Repository | GitHub | Branch | Verified commit |
| --- | --- | --- | --- |
| iOS frontend | `https://github.com/P-B-LLC/IOS-Frontend.git` | `main` | `5981b59` |
| Django backend | `https://github.com/P-B-LLC/repbase.git` | `main` | `0f527c8` |

Every commit below was built on the Mac from a clean clone of `main` before
being pushed.

> **Check the branch before doing anything.** `ui/repbase-redesign` was
> fast-forwarded into `main` on August 15 and `main` is now the trunk — new work
> goes on `main`, and the old branch is kept only as a marker of where the
> merge happened. Run `git status -sb` first: a clean-clone build of `main` once
> reported success while verifying nothing about the change in hand, because the
> change was sitting on the branch.

## Start here

Before changing code, read these in order:

1. `AGENTS.md` — mandatory repository and API-boundary rules.
2. `API/openapi.yaml` — canonical backend contract.
3. `API/API.md` — supporting notes.
4. `API/INTEGRATION.md` — iOS/API architecture and known gaps.

Do not invent endpoints, fields, response bodies, enum values, query parameters,
or ownership behaviour. If a feature is not in the OAS, either keep it
explicitly local or change the backend contract first. Both happened this
session and both are described below.

## Repository locations

```text
Windows (iOS, pushes to GitHub)   D:\IOS-Frontend Folder on Laptop\IOS-Frontend
Mac (iOS build/test copy)         /Volumes/Macintosh_HD/Users/user299988/Documents/IOS-Frontend
Mac (Django backend)              /Volumes/Macintosh_HD/Users/user299988/Documents/repbase
```

The backend exists **only on the Mac**. It is edited in place over SSH and never
cloned to Windows, except transiently when pushing (see below).

## SSH into the Mac

```powershell
ssh -i "C:\Users\Aaron\.ssh\codex_macincloud_tx087_ed25519" -o UserKnownHostsFile="C:\Users\Aaron\.ssh\known_hosts_codex_tx087" user299988@TX087.macincloud.com
```

Expect `whoami` = `user299988`, `hostname` = `TX087-I`. Adding
`-o BatchMode=yes -o ConnectTimeout=25` makes one-shot commands fail fast rather
than hang. The private key stays on Windows and must never reach source control,
chat, or logs.

### The Mac cannot push to GitHub

Confirmed again this session. Its credential helper is `osxkeychain` and the
login keychain is locked over SSH (`failed to get: -25308` → "could not read
Username"), and there are no SSH keys for GitHub. **Never try to unlock the
keychain** — that needs the user's password.

To publish a backend commit, relay it through Windows:

```powershell
# On the Mac
git bundle create /tmp/be.bundle main
# Copy to Windows, then
git clone --branch main <bundle> <scratch dir>
git remote add origin https://github.com/P-B-LLC/repbase.git
git fetch origin main
git merge-base --is-ancestor origin/main HEAD   # verify fast-forward FIRST
git push origin main
# Delete the temporary clone afterwards
```

Always verify the fast-forward before pushing, and tell the user, since this
briefly places backend source on their laptop.

To update the Mac's iOS copy, bundle from Windows and `git merge --ff-only`. The
Mac's `origin/main` tracking ref is stale and may report "ahead N"; this is
expected. Never `reset --hard` to silence it.

## Build and run

```text
Xcode 26.6 (17F113), macOS 26.3
Simulators: iPhone 17 Pro C0B019D8-A7DA-4470-AA96-A75F6ECE7B1D
            iPhone 17     498BF02E-6003-408B-BBB6-262EB87627E8  (used latterly)
Bundle ID:  P-B-LLC.IOS-Frontend
Deployment: iOS 26.5
```

```bash
cd '/Volumes/Macintosh_HD/Users/user299988/Documents/IOS-Frontend'
xcodebuild -project 'IOS Frontend/IOS Frontend.xcodeproj' \
  -scheme 'IOS Frontend' -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=498BF02E-6003-408B-BBB6-262EB87627E8' \
  -derivedDataPath /tmp/cli-dd build
```

**Do not add `CODE_SIGNING_ALLOWED=NO`.** It was used for most of this session
and it silently breaks staying signed in: an unsigned app cannot reach the
Keychain, so the token is never stored and every launch lands on the login
screen. The default signs locally with "Sign to Run Locally", which works.
Measured rather than reasoned about — launch with
`SIMCTL_CHILD_REPBASE_KEYCHAIN_CHECK=1` and the app reports which it is:

```text
signed                    KEYCHAIN-CHECK works
CODE_SIGNING_ALLOWED=NO   KEYCHAIN-CHECK unavailable
```

Then install from `/tmp/cli-dd/Build/Products/Debug-iphonesimulator/IOS Frontend.app`.

### Build environment gotchas, all hit this session

- **Xcode being open holds the build database lock.** Symptom: `unable to attach
  DB … database is locked`. Do not kill the user's Xcode — build with a separate
  `-derivedDataPath` instead.
- **`CODE_SIGNING_ALLOWED=NO` produces an app with no entitlements**, so every
  Keychain call fails with `-34018` (`errSecMissingEntitlement`) and **the user
  has to sign in on every launch**. The token store tolerates it rather than
  crashing, which is what made it easy to miss. Build signed and the problem
  disappears; the app code needed no change.
- **Do not locate the built app with `find … -print -quit`.** It can return an
  `Index.noindex` artifact that fails to install with "Missing bundle ID".
  Exclude it: `-not -path '*Index.noindex*'`.
- **`plutil -extract` rewrites the file in place** unless given `-o -`. It
  silently destroyed a built `Info.plist` mid-session. Use `plutil -p | grep`
  to inspect.
- **SwiftUI type-checker timeouts.** `DayWorkoutView.body` grew until it failed
  with "unable to type-check this expression in reasonable time". It is now split
  into `body` → `styledContent` → `content`. Expect to split again as it grows.
- **Text drawn on the canvas needs the canvas colours.** `HomeTimeOfDay` has
  `canvasPrimaryText` / `canvasSecondaryText` / `canvasBorder` / `hasDarkCanvas`
  alongside the usual ones. A raised surface stays light at every hour, so
  `primaryText` follows the *appearance*; the canvas itself goes dark from
  **dusk**, so anything unraised must follow the *canvas* or it sinks into the
  gradient. The home to-do list and the planner's hour grid are the two things
  drawn that way.
- **`role: .destructive` reddens a button's text but not its icon**, and
  `.tint(.red)` on the button does not reach it either. The label has to carry
  `.foregroundStyle(.red)` itself.

### Verifying UI

`xcrun simctl` has **no tap, swipe, or scroll command**, `idb` is not installed,
and `osascript` UI scripting fails over SSH (`-1743`). Any screen reachable only
by tapping cannot be captured programmatically — say so rather than claiming it
was seen. For long scrolling pages, launching on an **iPad** simulator often fits
the whole page in one screenshot; pick one on the **iOS 26.5** runtime, as several
iPads sit on an 18.0 runtime and refuse to install the app.

## Run the development backend

```bash
cd '/Volumes/Macintosh_HD/Users/user299988/Documents/repbase'
source .venv/bin/activate
nohup python manage.py runserver 127.0.0.1:5000 > /tmp/django.log 2>&1 < /dev/null &
```

Debug builds target `http://localhost:5000/`. The server is frequently **not**
running; check with `lsof -nP -iTCP:5000 -sTCP:LISTEN` before assuming the API is
reachable. When it is down, `connect()` fails and every editing control in the
app disables itself (with an explanation, since this session). The symptom in
the app is a wall of red text ending in
`NSURLErrorDomain Code=-1004 "Could not connect to the server"`.

Two things about starting it:

- **Redirect all three streams and background it, or it dies with the session.**
  A server started from an agent's background SSH task is killed when that task
  is torn down, which has already happened once. `nohup … > log 2>&1 < /dev/null &`
  survives; **`setsid` does not exist on macOS** and fails with
  `command not found`, silently leaving nothing running.
- It binds **`127.0.0.1`**, not `0.0.0.0`. The simulator shares the host's
  network stack, so `localhost:5000` reaches it either way, and the public bind
  was drawing scans from the internet (`DisallowedHost … '216.14.167.87:5000'`
  in the log). Use `0.0.0.0` only if a physical device on the LAN needs it.

`POST /api/v1/auth/register/` requires `username, email, password, first_name,
last_name`. There is no `password_confirm`.

### After pulling the backend

```bash
python manage.py migrate
```

Profile photos need **Pillow**, which `ImageField` requires:

```bash
pip install -r requirements.txt
```

There are now **eleven new migrations** (`0004`–`0014`). Without them the API
errors on the new fields and the app cannot connect.

## What changed since `ad1df5b`

### Workout types and cardio

Workouts are now **lifting, running, biking, or swimming**. Picking a distance
type replaces the exercise planner with a single effort, and such a workout needs
no planned exercises to start.

- Backend: `WorkoutTemplate.workout_type` (defaults to `lifting`, so existing
  rows stay valid) and `SetEntry.distance_km` (kilometres, matching the existing
  kg convention).
- Scheduling **reuses an existing workout of the same name** instead of failing
  the unique-name constraint. A template is meant to be scheduled on many dates.

### GPS route tracking

A run, ride, or swim records its route; the user types nothing.

- `RouteTracker` (`Services/RouteTracker.swift`) records fixes only while a
  session is active, and stops on end or discard.
- Live readout during the activity: **distance, pace (or km/h for a ride), and
  climb**, plus a map of the route so far. These are labelled live estimates.
- On ending, the track is uploaded and the **backend** computes the recorded
  figures: distance, pace, moving pace, average and top speed, moving time,
  elevation gain/loss, and per-kilometre splits.

Accuracy work, all verified against synthetic tracks with known answers:

- **Speed comes from the GPS Doppler reading** (`CLLocation.speed`), not derived
  from positions, so it carries no accumulated positional error.
- **Elevation comes from the barometer** (`CMAltimeter`), not GPS. GPS height is
  often several metres out — enough to invent hills. One GPS reading anchors the
  series to sea level; every change after that is barometric.
- **Distance ignores stationary drift.** A phone's position wanders metres
  between fixes when still; ten minutes on a bench previously logged about a
  kilometre. Distance now only accumulates while the device reports movement, on
  both the device and the server. Verified: stationary → `0.0 km`, real run →
  `1.0 km`.
- Fixes worse than **25 m** accuracy are dropped (was 100 m), stale replayed
  fixes are ignored, and jumps faster than 30 m/s are treated as bad fixes.
- **Elevation needs smoothing *and* hysteresis.** Neither works alone: a
  threshold alone reported 12 m of climb on flat ground; smoothing alone
  accumulated 23.6 m of residue over hundreds of fixes. Together: flat ground
  `0.0 m`, a real 100 m hill `95.2 m`. It under-reports slightly by design.

Permissions (Apple requirements): `NSLocationWhenInUseUsageDescription`,
`NSMotionUsageDescription`, and `UIBackgroundModes: [location]`, all verified
present in the built bundle.

**Note on `Info.plist`:** Xcode's generator silently ignores
`INFOPLIST_KEY_UIBackgroundModes`. A partial `IOS Frontend/Info.plist` is merged
with the generated keys via `INFOPLIST_FILE`. It **must sit beside the project,
not inside the synchronized source group**, or Xcode both copies and processes it
("Multiple commands produce"). Background updates are additionally gated on the
bundle actually declaring the mode, since CoreLocation raises otherwise.

### Progress, records, and charts

- **Runs**: a line chart of past sessions, toggling distance and pace. The pace
  axis is **inverted** for running and swimming so "up" always means improving.
- **Lifting**: a line chart per exercise of heaviest set and total volume,
  plus a list of **personal records** set that session.
- Records are computed by the backend at `GET /api/v1/sessions/{id}/records/`,
  comparing against every set logged before. Two kinds: heaviest single lift, and
  best estimated one-rep max (Epley, ignoring sets over 12 reps). The estimate
  catches progress raw weight misses — 67.5 kg × 5 beats a 70 kg single.
  A session cannot beat itself, and repeating a workout reports nothing.
- **All history is matched by workout _name_**, not template id. This matters:
  the same exercise trained in two differently-named workouts previously shared
  one history, so a heavier lift in one made the other look like a regression.
- Naming a workout now lists **previously used names**; tapping one takes the
  name exactly and its type with it, so a near-miss spelling cannot split a
  workout's history in two.

### The profile and gyms

Account creation is a four-page flow (`ProfileOnboardingView`), reached from
**Create Account** on the sign-in screen rather than from a form on it.

- **Page 1 creates the account with email and password.** It is meant to be
  Sign in with Apple / Google, and cannot be: that needs an Apple Developer
  membership, the `com.apple.developer.applesignin` entitlement, and a Google
  client id, and these builds run `CODE_SIGNING_ALLOWED=NO` with **no
  entitlements at all**. The user chose email/password now, social later. The
  page says so rather than showing two dead buttons.
- **A gym is a shared row**, not text on a profile. `normalized_name` +
  `normalized_city` are unique together, so a near-repeat is refused by the
  database. **Apostrophes are dropped, not replaced** — replacing made `Gold's`
  into `gold s`, which then failed to match `Golds`, the very duplicate the key
  exists to catch.
- **Three visibility switches**, not one: `shows_height` / `shows_weight` /
  `shows_target_weight`. One flag could not say "share my height but not my
  weight". Withheld values come back as **null rather than a missing key**, so
  the response keeps its shape.
- **Disciplines are a row each** (`UserDiscipline`), not a JSON list: JSON
  containment is unsupported on SQLite, so a list would make "who else here
  climbs" unanswerable. Sending a list **replaces the set wholesale**.
- **Photos upload as base64 over JSON** to `PUT /api/v1/me/photo/`, not
  multipart, so the generated client needs no separate upload path. The old
  file is deleted on replacement. `DATA_UPLOAD_MAX_MEMORY_SIZE` is raised to
  8 MB because Django's 2.5 MB default sits **below** a 5 MB photo once base64
  adds a third, so the photo limit would never have been what refused.
- iOS maps disciplines **explicitly, not by `rawValue`**: the app's raw values
  are the words on screen and the server's are its identifiers. `GymIdentity`
  carries `serverID`; without it two people picking the same gym each held
  their own local UUID and never matched. Pounds convert through `Decimal`,
  since weights travel as decimal strings and a `Double` turns 82.5 into
  82.499999.

**Still local:** the onboarding views read and write `SocialProfile` directly,
so the gym picker builds local `GymIdentity` values instead of calling
`searchGyms` / `createGym`. The plumbing exists in `SocialProfileStore`; the
views need pointing at it.

> **Decorator order is load-bearing.** `@extend_schema_view` applies to the
> class that follows it. Inserting a new viewset between an existing decorator
> and its class stacks *both* onto the new one and silently strips the
> parameters off the old — which happened to `PlannerEntryViewSet` and only
> surfaced when the iOS build failed. Nothing in the API changes behaviour,
> only its description of itself, so a schema diff is the way to catch it.

### The planner

A page of its own, reached from the bottom bar: a month calendar that steps
through any month of any year, the week in focus, **Add Task** / **Add Event**,
and the day's list.

- A **task** is finished or not and carries a checkbox. An **event** happens at
  a time and is never completed — asking to complete one is a **400**, not a
  quietly ignored field.
- **Categories are split by kind.** A task is sorted by what kind of doing it
  is (habit, workout, errand, study, sleep, health, work, home); an event by
  what kind of occasion it is (birthday, holiday, appointment, meeting, travel,
  social). `other` is the only one both share and the fallback when the kind is
  switched. The pairing is enforced server-side against **what the row will end
  up as**, not just what the request carries, so flipping a habit task to an
  event cannot strand the category on it.
- Picking a day on the calendar carries that day into the editor, so a task
  planned for a Thursday is not silently filed under today.
- Completion is stored as **`completed_at`, a timestamp**, and exposed as a
  writable `is_complete`. Editing a task's name therefore cannot untick it.
- A **workout** task can point at a real `WorkoutTemplate`, which is what
  connects this page to the workout page.
- The **month** is the unit that gets loaded, padded a fortnight either side for
  the grid's borrowed days. The week strip and the day list are slices of that
  same data, not extra requests that could disagree with it.
- The day is drawn **against the clock**: an hour grid with each timed entry at
  the hour it starts, and untimed ones listed beneath under **ANYTIME** rather
  than placed at an hour the user never chose. **Blocks are a fixed height** —
  an entry records a start and nothing about length, so sizing one to a
  duration would draw data that does not exist. Add `end_time` first if that
  is ever wanted.
- The **month is closed by default**; the week strip's month name opens it and
  its own ✕ closes it. The day tabs could not carry that: they already mean
  "choose this day".
- **Past due** and **Upcoming events** are separate sections. Past due is
  fetched with **no lower bound** (`?kind=task&is_complete=false&end=<yesterday>`)
  — overdue work is unbounded in time, and fetching a window would silently
  drop anything older than it. Upcoming looks `PlannerStore.upcomingHorizonDays`
  (60) ahead and **says so on screen**, so a short list means an empty diary
  rather than a hidden cutoff.
- Entries are deleted from **the editor** (a `Delete Task` / `Delete Event` row
  at the bottom, only when editing something that exists) or by **long press**
  on a row. Not by swipe: the rows sit in a `ScrollView`, not a `List`, where
  `swipeActions` would never fire.
- Sorting a day puts **timed entries first, untimed last**. An absent time is
  an empty string, which sorts *before* every real one — that had untimed tasks
  leading the home list instead of trailing it.
- `role: .destructive` reddens a button's text but leaves its icon on the accent
  tint, and `.tint(.red)` on the button does not reach it either. The label has
  to carry `.foregroundStyle(.red)` itself.

Verified by three probes, 51 checks: completion round-trips, renaming a done
task leaving it done, blank names rejected, another user's workout rejected,
inclusive date ranges, untimed entries sorting before timed ones, and every
task/event category pairing accepted or rejected as it should be. One real bug
caught before it shipped — the generated client typed `workout_name` as
non-optional `String` while the API sends `null` for anything without a
workout, so every ordinary task would have failed to decode. Fixed in the
contract, not worked around.

`REPBASE_PLANNER_PREVIEW` boots the app straight into one screen, the same trick
`REPBASE_FOOD_PREVIEW` uses. DEBUG-only, and it skips the network entirely.

```text
REPBASE_PLANNER_PREVIEW=1             the planner page, with sample data
REPBASE_PLANNER_PREVIEW=home          the whole home page, workouts included
REPBASE_PLANNER_PREVIEW=task-editor   the new-task sheet
REPBASE_PLANNER_PREVIEW=event-editor  the new-event sheet
REPBASE_PLANNER_PREVIEW=edit-editor   an existing event, so Delete shows
```

**Use these.** The editors are sheets, reachable only by tapping, and the
simulator has no tap command — without the flags they ship unseen. Two real
problems surfaced this way: a build installed on the phone that predated a
feature and looked like the feature was broken, and the destructive-icon tint
above. Launch with
`SIMCTL_CHILD_REPBASE_PLANNER_PREVIEW=<value> xcrun simctl launch …`, and
**relaunch without it afterwards** — otherwise the user is left looking at a
one-page app with fake data and no navigation, which reads as everything else
having disappeared.

### Weekly repeats

A day's workout carries a **"Repeat every Monday"** toggle. Before this, a
schedule was a literal `YYYY-MM-DD` and next Monday was always empty.

**Decided by the user on August 15: a change applies from that week forward,
never backwards.** A `WorkoutRecurrence` therefore covers the half-open range of
weeks `[effective_from, effective_until)`, both Mondays. Turning a repeat off
closes it at the current week instead of deleting it, so weeks that already
happened keep resolving through the plan that was in force then. The rejected
alternative — one mutable rule every week reads live — would have made last
month's Mondays show a workout that was never trained, while the logged session
said otherwise, and the progress charts match by name.

Consequences worth knowing:

- `POST /api/v1/schedules/plan-week/` fills a week in on demand, and the app
  calls it at the start of every `loadWeek`. It is idempotent, and it **refuses
  to plan a week that has already finished**.
- Each rule remembers how far ahead it has planned, so **a day the user deletes
  stays deleted** rather than reappearing on the next load.
- Schedule rows remember the rule that created them (`source_recurrence`), so
  ending a repeat clears the weeks ahead and **leaves days chosen by hand
  alone**. Without that link, "same workout, same weekday" cannot tell a planned
  day from one the user added.
- There is **no update endpoint**, deliberately. Changing a repeat is ending one
  and starting another, which is what preserves the past.
- The API numbers Monday as `0` and the app's `Weekday` numbers it as `1`. The
  conversion lives on `Weekday.apiValue` / `init(apiValue:)`, nowhere else.

Verified against the live API by two probes: sixteen checks covering
immutability of finished weeks, idempotence, deleted days staying deleted, hand-
chosen days surviving, and duplicate repeats returning 400; then seven more
pinning the weekday arithmetic to real calendar dates. **The toggle itself has
not been tapped** — the simulator cannot be driven programmatically.

### Cardio finisher

A lifting workout can end on a machine — treadmill, bike, stair master,
elliptical, rower, assault bike, ski erg, or other — with an optional minute
target, chosen while planning it.

The finisher **belongs to the workout it follows**, which is the whole point of
the design. It is stored on the template and on the session, shown at the bottom
of that day's workout rather than as a second scheduled workout, and started
from the summary once the lifting session ends. `POST
/api/v1/sessions/{id}/cardio/` writes it onto that same session, so a workout
and the cardio after it stay one training session. Verified: one schedule for
the day, one session, and an invalid machine rejected with 400.

The machine is preselected from the plan but changeable, since the one that was
free is not always the one intended, and distance can be read off the machine
and recorded with it.

### Day and session flow

- Each day's workouts are **separate swipeable pages** when a day holds more
  than one; day tiles carry a count badge.
- A day's workouts can each be started, edited, or removed independently.
- **No destructive action asks for confirmation any more**, at the user's
  explicit request: ending a session, removing a workout from a day, discarding
  a session, and removing a meal all act on the first tap. Each button names
  what it does and which day or meal it does it to. The one to watch is the bare
  **X** on an active session, which now discards logged sets outright; the user
  was told and chose it. Do not reintroduce a confirmation sheet without asking.
- The completion summary reports distance, pace, and climb for a run rather than
  sets and a completion percentage, which described lifting and read as "0%" for
  a finished 5 km.

### Food tracking

- "Add Food" opens a **picker**: previously used foods for one-tap reuse
  (searchable, each reuse an independent copy), a food-database row that stays
  visibly unavailable, and manual entry as a secondary action.
- The **"Log Meal" button is gone**; a meal holding food counts as logged.
- A **Nutrition Breakdown** on the food page and each meal: calorie split,
  which foods supply each macro, and per-meal composition.
- Foods are **classified by their dominant macro** and tagged, so a mixed food
  no longer appears as an equal source of all three. A food is listed under a
  macro only when that macro is its primary one or supplies at least a quarter
  of its calories; the remainder rolls into "Other foods" so percentages still
  reconcile.
- Vitamins and micronutrients are **stated as unavailable**, not invented. The
  OAS has no nutrition endpoints; food tracking remains local and in-memory by
  design, and must not make undocumented calls.

### Fixes worth knowing about

- **Sign-in was impossible.** Django REST emits microseconds
  (`2026-08-14T20:43:46.889254Z`) and omits them when zero; the runtime's default
  transcoder rejects fractional seconds outright, so every authenticated response
  failed to decode. `RepbaseDateTranscoder` now reads both forms. Accounts were
  being created while the app reported an error.
- **The day editor could wedge permanently.** `reloadWeek` only cleared
  `isLoading` when the connection generation still matched, so a reconnect
  mid-load left it set forever, disabling every control with nothing on screen —
  and `retryPersistence` refused to run because it guarded on `!isLoading`. Flags
  are now cleared however an operation exits, and disabled controls explain why.
- **A duplicate workout name returned HTTP 500.** Names are unique per owner, but
  `owner` is read-only and assigned while saving, so the generated validators
  never saw it and the database constraint escaped as an unhandled
  `IntegrityError`. Now a normal validation error — and the app reuses the
  existing workout instead.
- **Keychain writes blocked sign-in on simulator.** Reading already tolerated the
  missing entitlement; writing threw, and sign-in saves the token before marking
  the session active. Writing and deleting now match reading. Sessions do not
  survive relaunch on a CLI-built simulator app.

## Contract additions this session

All additive; nothing was removed.

```text
Gym                                     name, city, country, member_count
GET/POST/PATCH/DELETE /api/v1/gyms/     ?search=
GET      /api/v1/gyms/{id}/members/     who trains there
RepbaseUser.bio, shows_height, shows_weight, shows_target_weight,
           disciplines[], gym (FK), profile_photo_url (read-only)
UserDiscipline                          one row per discipline
PUT/DELETE /api/v1/me/photo/            {content_type, image_base64}

PlannerEntry                            kind (task|event), title, category,
                                        scheduled_date, scheduled_time,
                                        is_complete (write) / completed_at
                                        (read), workout, workout_name, notes
GET/POST/PATCH/DELETE /api/v1/planner/  ?start=&end=&category=&kind=
                                        &is_complete=

WorkoutRecurrence                       workout, weekday (0 = Monday),
                                        effective_from, effective_until
                                        (both read-only, both Mondays)
WorkoutSchedule.source_recurrence       internal; not serialized
GET/POST/DELETE /api/v1/recurrences/    no update endpoint, on purpose
POST     /api/v1/schedules/plan-week/   {start} -> that week's schedules

WorkoutTemplate.workout_type            lifting | running | biking | swimming
WorkoutTemplate.cardio_machine          nullable; cardio_target_minutes
WorkoutSession.cardio_machine, cardio_seconds, cardio_distance_km
POST     /api/v1/sessions/{id}/cardio/  record the finisher performed
SetEntry.distance_km
SessionRoutePoint                       lat, lon, recorded_at, speed_mps, altitude_m
WorkoutSession.route_distance_km, pace_seconds_per_km, moving_pace_seconds_per_km,
               average_speed_kmh, max_speed_kmh, moving_seconds,
               elevation_gain_m, elevation_loss_m, splits[]
ExerciseProgressPoint.session

GET/POST /api/v1/sessions/{id}/route/    read or append the GPS track
GET      /api/v1/sessions/{id}/records/  personal records set by a session
GET      /api/v1/sessions/?status=&workout=&workout_name=
GET      /api/v1/progress/exercises/{id}/?workout_name=
```

Regenerate the client on macOS after any contract change:

```bash
bash Scripts/generate-api-client.sh
```

Never hand-edit `API/GeneratedSources`. Two contract mismatches were caught by
the compiler this session and are worth remembering:

- A custom `@action` returning `Response(serializer.data)` is **not** paginated,
  but `drf-spectacular` documents `many=True` as a paged envelope when the view
  has a paginator. Set `pagination_class=None` on the action.
- An action returning `201` while the schema said `200` made the generated client
  treat every success as undocumented.
- A choice field with **both** `blank=True` and `null=True` generates a
  three-case union (enum | blank | null) in every client. Declaring the
  serializer field as `ChoiceField(required=False, allow_null=True)` reduces it
  to two. The null half is an `OpenAPIRuntime.OpenAPIValueContainer`, so
  building one requires `import OpenAPIRuntime` in the app file.
- A serializer named `SessionCardioRequestSerializer` generates
  `SessionCardioRequestRequest`. Name request serializers without the suffix.

## Known limitations and next decisions

1. **Repeats are new and have not been used across a real week boundary.** The
   logic is verified against the API (see below), but nobody has yet opened the
   app on a Monday and watched the week fill in. That is the one thing worth
   checking first.
2. **Nothing has been verified by tapping.** Every UI change this session is
   compile-verified and, where possible, verified through the API. The simulator
   cannot be driven programmatically. GPS and the barometer in particular need a
   real device — simulator location is synthetic and there is no barometer.
3. **Food data is in memory only.** Entries, goals, and saved recipes are lost on
   restart or sign-out. Do not build a pretend food backend; add nutrition to the
   OAS first, regenerate, then replace the local store boundary.
4. **No XCTest target and no CI.** The only validation gate is an Xcode simulator
   build on the Mac plus manual review. Given how many real bugs surfaced this
   session through scripted API probes, a test target would be worth real money.
5. The OAS declares no stable error schemas, so failure messaging stays generic.
6. Schedule uniqueness and timezone behaviour remain contract gaps.
7. `ROADMAP.md` and the local `db.sqlite3.backup-before-workout-type` are
   intentionally untracked. Preserve them.
8. The dev database contains probe accounts created while verifying
   (`claude_*`, `pr_*`, `hist_*`, `name_*`, and similar) and some implausible
   test data — Pullups logged at 300 kg × 12, which suppresses genuine PRs on
   that exercise.

## Expected working style

- Read `git status` before editing and preserve unrelated changes. The user has
  edited files in parallel this session; changes were silently reverted twice
  before their in-progress work was committed.
- Verify claims rather than asserting them. Scripted API probes against the live
  backend caught several real bugs this session that reading code did not:
  a vanishing final split, absurd average speeds, phantom elevation on flat
  ground, and a kilometre of distance from a stationary phone.
- Build on the Mac before reporting an iOS change complete, and verify the
  **committed** state from a clean clone before pushing — commits have excluded
  files that the working tree still had.
- Keep calculations on the backend. The device shows live estimates; the server
  produces the recorded figures.
- Preserve the compact, professional visual direction, and the prepare / focus /
  recover phases in `WorkoutPhaseTheme.swift`.
- Keep meal names numbered, and each workout day and food date independently
  editable.
- Commit coherent changes on Windows, push `main`, then update the Mac. Ask
  before pushing; the two repositories are separate remotes and each needs its
  own permission.
