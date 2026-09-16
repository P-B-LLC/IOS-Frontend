# Repbase iOS — Work History and Claude Handoff

Last updated: August 23, 2026 (custom activity icon system)

This supersedes the previous handoff, which described the project at `ad1df5b`.
Everything in that document still worth keeping has been folded in here.

| Repository | GitHub | Branch | Verified commit |
| --- | --- | --- | --- |
| iOS frontend | `https://github.com/P-B-LLC/IOS-Frontend.git` | `main` | `64aa5cd` |
| Django backend | `https://github.com/P-B-LLC/repbase.git` | `main` | `c1029f4` |

## August 23 UI context — custom activity icons

The user rejected the previous hand-drawn `Canvas` workout figures and approved
the compact sports-pictogram family shown in:

- `DesignReferences/activity-icon-reference.png` — committed source reference.
- Figma file `zavGrRPLRkrcKfcVlpDVcR`, node `488:2` — the 15-icon replacement
  audit and screen-usage inventory. The Figma connector required
  reauthentication on August 23; the source image is therefore the durable
  repository reference.

`Views/Shared/WorkoutInkArtwork.swift` is now the single semantic icon entry
point. `ActivityIconKind` contains all 15 approved roles and
`ActivityIconArtwork` performs template rendering so selected/unselected,
light, and night colors come from each screen. `WorkoutInkArtwork` remains only
as a compatibility wrapper and no longer draws figures with `Canvas`.

The custom activity set covers:

1. Lifting, running, biking, and swimming.
2. Treadmill, stationary bike, Stair Master, elliptical, rower, assault bike,
   Ski Erg, and other cardio.
3. The cardio-section mark, running-shoe gear mark, and bike-gear mark.

The running-shoe role intentionally reuses the already-approved
`RepbaseSpeedSole` vector. The other assets are in
`Assets.xcassets/Activity*.imageset`. The deterministic extraction script is
`Scripts/build-activity-icon-assets.ps1`; rerunning it rebuilds the tintable PNG
assets from the committed reference without generative reinterpretation.

All workout/cardio/gear `symbolName` APIs were removed so new call sites cannot
quietly return to the rejected SF Symbols. Utility symbols such as back, add,
check, delete, navigation, and the steps walking mark are intentionally outside
this activity-icon scope.

Every commit below was built on the Mac from a clean clone of `main` before
being pushed.

> **Read "The three-day-old bug" and "Expected working style" before writing
> code.** Most of what went wrong on August 18–19 was caught by running
> something, and missed by reading it. Two bugs shipped because the code looked
> right.

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
Windows laptop  (iOS, pushes)   D:\IOS-Frontend Folder on Laptop\IOS-Frontend
Windows desktop (iOS, pushes)   C:\IOS Frontend\IOS-Frontend
Mac (iOS build/test copy)       /Volumes/Macintosh_HD/Users/<mac-user>/Documents/IOS-Frontend
Mac (Django backend)            /Volumes/Macintosh_HD/Users/<mac-user>/Documents/repbase
```

**There are two Windows machines, and they are not interchangeable.** Each has
its own clone and its own SSH key situation; the desktop's key was generated on
August 18 and added to the Mac's `authorized_keys` alongside the laptop's. Check
which one you are on before trusting a path in this document.

**More than one agent session works this repository at once**, sometimes in the
same working tree. Run `git status` before editing and again before committing,
and stage your own files by name — `git add -A` swept another session's
in-progress work into three commits on August 18 before this was written down.

The backend exists **only on the Mac**. It is edited in place over SSH and never
cloned to Windows, except transiently when pushing (see below).

## SSH into the Mac

The placeholders below are deliberate. This repository is public, and a
hostname next to a username is an SSH target anyone can start guessing at.
The real values are with the machine's owner and in the assistant's local
memory for this project; they are not written down here.

They are still in this repository's git history, which publishing cannot
undo. This stops casual discovery, not a determined search — so the Mac
should be on key-only authentication, and the key itself has never been in
source control.

```powershell
ssh -i "C:\Users\Aaron\.ssh\<mac-ssh-key>" -o UserKnownHostsFile="C:\Users\Aaron\.ssh\<mac-known-hosts>" <mac-user>@<mac-host>
```

Expect `whoami` to match `<mac-user>`. Adding
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

**Never guess the base revision of a bundle.** Read it off the Mac:

```bash
MACHEAD=$(ssh … "git -C /tmp/rb-hk rev-parse HEAD")
git bundle create /tmp/x.bundle "$MACHEAD..main"
```

A bundle whose base the Mac does not have fails the fetch with a bare
`error: <sha>` and then `Already up to date.` — after which the build runs
happily on the **old** tree and prints `** BUILD SUCCEEDED **`. That happened
twice in one afternoon. Have the build script echo `git log --oneline -1` and
grep the tree for the change before compiling, and read those lines rather
than the exit code.

To update the Mac's iOS copy, bundle from Windows and `git merge --ff-only`. The
Mac's `origin/main` tracking ref is stale and may report "ahead N"; this is
expected. Never `reset --hard` to silence it.

## Build and run

```text
Xcode 26.6 (17F113), macOS 26.3
Simulators: iPhone 17 Pro C0B019D8-A7DA-4470-AA96-A75F6ECE7B1D
            iPhone 17     498BF02E-6003-408B-BBB6-262EB87627E8  (used latterly)
Bundle ID:  com.pbllc.rytivo   (was P-B-LLC.IOS-Frontend until Sept 2)
Deployment: iOS 26.5
```

```bash
cd '/Volumes/Macintosh_HD/Users/<mac-user>/Documents/IOS-Frontend'
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

Then install from `/tmp/cli-dd/Build/Products/Debug-iphonesimulator/Rytivo.app`.

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

**It is a launchd agent now and starts itself.** `~/Library/LaunchAgents/
com.repbase.devserver.plist`, installed August 18, runs it at login and
restarts it if it exits. The Mac rebooted three times that day and the third
reboot was the first that did not leave the user staring at a connection error.

```bash
launchctl list | grep repbase                    # is it registered
lsof -nP -iTCP:5000 -sTCP:LISTEN                 # is it listening
launchctl kickstart -k gui/$(id -u)/com.repbase.devserver   # restart it
tail -f ~/Library/Logs/repbase-devserver.log     # its log
```

> **The agent runs `--noreload`, so it does not pick up code changes.**
> Kickstart it after **every** backend edit. Not doing so served a serializer
> from before the change and the app failed with
> `DecodingError.keyNotFound: 'logged_set_count'` — a contract-first client
> pointed at a stale server. The autoreloader is off on purpose: it forks a
> child, and launchd then supervises the wrong process.

> **When a restart looks like a failure, it is usually not.** `kickstart -k`
> SIGTERMs the process (`launchctl list` shows `-15`) and launchd starts a new
> one a moment later. Checking the port once, immediately, reports nothing and
> reads as "the backend is down"; that false alarm was raised twice. Poll for
> the port for ~45 seconds instead.

The log lives in `~/Library/Logs/`, deliberately **not** `/tmp` — a reboot
clears `/tmp`, which is how the previous log, every build directory and several
scratch files disappeared mid-session. Assume nothing in `/tmp` survives.

Started by hand instead, the old way still works:

```bash
cd '/Volumes/Macintosh_HD/Users/<mac-user>/Documents/repbase'
source .venv/bin/activate
nohup python manage.py runserver 127.0.0.1:5000 > /tmp/django.log 2>&1 < /dev/null &
```

Debug builds target `http://localhost:5000/`. When the server is down,
`connect()` fails and every editing control in the app disables itself (with an
explanation). The symptom in the app is a wall of red text ending in
`NSURLErrorDomain Code=-1004 "Could not connect to the server"`. That error
always means the backend is not answering — never a wrong password.

Two things about starting it by hand:

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
  **One exception, added August 19 at the user's request:** finishing a session
  that logged **no sets at all** asks first. That is not a confirmation of
  intent but a correction of a likely mistake — three sessions on the dev
  account were finished holding nothing, because typing in the boxes does not
  save a set and nothing said the circle does. Finishing real training still
  acts on the first tap.
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

## August 18–19: posting, performance, and the planner

### Posting to the feed

The feed could be read and never written to. The API, the store and all three
post kinds already existed; only the screen was missing, which is why the empty
state advertised sharing "from its page" when no such button existed anywhere.

`PostComposerView` has three ways in, and the difference matters:

- `init()` — from the feed's ✏️. Asks which feature, then which thing.
- `init(source:)` — from a feature's own page. Skips the first question, since
  the page has already answered it. Used by **Share a meal** on the food page
  and **Share a workout** on the workouts page.
- `init(kind:sourceID:subject:)` — from one specific thing. Shows what is being
  shared instead of a picker. Used by the completion summary and the calendar
  entry editor.

**Sharing lives on the page that lists things, not on each thing's own screen.**
The meal page had a Share; it was moved to the food page at the user's request,
because one screen per meal is the last place anyone looks to post. The workout
equivalent is on the workouts page. The completion summary keeps its own, since
that is the moment a workout is most worth posting and the only place holding a
session that has just been created.

**A `ToolbarItem` is invisible in this app.** The meal's first Share was one,
and this app hides the navigation bar on eleven screens. Put controls in the
page.

### Photos on posts

`Post.image`, base64 over JSON like the profile photo, carried on the create
rather than uploaded afterwards: a post is made once, and a second request to
attach the picture can fail on its own and publish a post without the thing its
caption is about. Files are named from the post id and a random suffix, never
from the uploaded filename.

The type is read from the **magic number**, not from the picker.
`PhotosPickerItem.supportedContentTypes` is often empty for a library asset and
there is no filename to take an extension from. JPEG, PNG, WEBP and the HEIF
`ftyp` box are recognised; anything else is refused in the sheet with a
sentence rather than by a 400 naming a field nobody saw. HEIC is sent as-is,
since the contract accepts it and re-encoding costs quality for nothing.

Verified end to end on August 19: a 4 MB photo posted from the app and served
back at `/media/post-photos/…`.

### Performance: stop reading whole tables

Measured, not guessed — fifteen requests on a cold launch, two of them
duplicates, and two reads that pulled entire tables to pick rows out of them.

- Opening a session read **every session-exercise row the account owns**. The
  backend already supported `?session=`; it was never declared in the OAS, so
  no generated client could ask for it. Declaring it was the whole fix.
- Saving a workout paged the **entire exercise catalogue** to match names.
  `/exercises/` now takes `?name=`.
- `loadWeek` read all workout templates, then `workoutLibrary()` paged the same
  table again, sequentially. One fetch serves both.
- Food read sixty-two days of meals per sign-in to draw one day, with four
  sequential awaits. Now a fortnight back and a week forward, three of the
  reads concurrent.

**The one that mattered got slower the more the app was used**, which is the
worst kind: invisible on a new account, crippling after a year.

**None of this was why the app felt slow.** The Mac was at load average 583,
peaking 974, with two *other tenants'* VMs taking 126% CPU and the disk
swapping. It is a shared box. Measure the host before optimising the app.

### A day is trained once

Starting Tuesday's workout six times read as six workouts and a met weekly goal
of one. A session is created by tapping Start, and every dashboard metric
counted sessions.

The dashboard counts **distinct days trained** — one workout name on one
calendar day — and every figure derives from that same collapse, so no two
numbers on the page can disagree. A finished day no longer offers Start; it
offers **Redo Session** (which clears the day first, because a second session
beside the first is the duplicate) and **Undo**, and shows what was logged.

**Completion is derived, never stored.** There is no `is_complete` flag on a
day: the badge and the counts are computed from the same sessions, which is why
Undo cannot leave them disagreeing. The cost is that Undo deletes the session
records.

**An empty session counts for nothing.** `WorkoutSession.logged_set_count` is
annotated onto the list query — a hundred sessions would otherwise be a hundred
extra counts — and only rows carrying a weight or reps are counted, since set
rows are created when a session starts and counting them all would call an
untouched session full.

### Previous-set hints

Each weight and reps field shows the last session's value as `Prev: 100`,
labelled because a bare faded number reads as a value already entered. It is
never written into the field: one tap on the circle would then log a weight
nobody lifted.

Sessions are walked back newest-first until one is found that actually logged
something, five at most. A session can be finished holding nothing, and three
in a row on the dev account hid every usable session behind them.

The caption says **circle**, not checkmark. The control is a circle until it is
tapped and becomes one.

### The planner's three identity bugs

All three had one cause, and it is the most useful thing in this section.

**A local id that changes every time a row is read is not an identity.** The
mapper builds `PlannerEntry` from each response and mints a fresh `UUID`, so the
same server row is held under different local ids in different lists — and a
saved copy comes back with a different id from the one just sent.

| Symptom | What actually happened |
| --- | --- |
| Ticked overdue task stayed on screen | `apply` replaced the row with the saved copy, renaming it; `retirePastDue` then looked up the id the caller started with, found nothing, and returned. Both its guards failed silently, so it looked like it had never been called. |
| Day showed a completed task as unticked | Past due and the month are separate reads. The update reached the list the change was made in and missed the other. |
| Delete would leave a ghost | Same, for removal. |

Compare by **server id** wherever two lists can hold the same row —
`PlannerEntry.isSameEntry(as:)` — and apply a saved copy under the id the row
already had, `identified(as:)`. The first two were fixed at the symptom before
the cause was found; the third was found by looking.

### Duplicate planner tasks, and deleted ones coming back

Seventeen rows for one Tuesday. The sync that puts a scheduled workout on the
calendar checked `entriesByDate` — the month the planner is showing — and it
runs at sign-in, before any month is read. `nil` read as "not linked yet", so
every launch added another copy. Sixteen rows were deleted from the dev
database, keeping a completed one where the group had been ticked off.

Two guarantees now stand behind it:

- `unique_workout_task_per_day`, a **conditional** constraint on
  `(owner, workout, scheduled_date)` where `kind='task' AND workout IS NOT
  NULL`. Two hand-written tasks on one day stay ordinary. The serializer
  refuses the duplicate first so it is a 400 naming the field rather than an
  `IntegrityError` escaping as a 500.
- `POST /schedules/sync-planner/`. Deciding on the phone meant treating
  "missing" as one thing, when it covers both a day never offered a task and a
  day whose task the user deleted. The second is an answer, and re-asking it
  every launch put deleted tasks back. `WorkoutSchedule.planner_synced_at` is
  set when the task is made and never cleared, so the server can tell them
  apart — the same reasoning as `source_recurrence` beside it.

**Past due is bounded to thirty days.** It was deliberately unbounded so nothing
fell off the back; in practice it returned every task ever missed and buried the
ones still worth doing.

### Two things only a tap could find

Both were reported by the user from a screenshot, after building, installing,
launching and screenshotting had all reported success. They are the argument
for the paragraph above about tapping.

**A decorative `Image` styled like a control is a button that does nothing.**
The session summary had a tick in a filled circle with a shadow — the same
shape every real control on that screen uses — and it was an `Image`, not a
`Button`. It compiled, rendered and screenshotted correctly. It also duplicated
the COMPLETE badge beside it, so removing it cost nothing. When a screen's
buttons all share a shape, anything drawn in that shape is claiming to be one.

**A modal can cover the thing it is describing.** The empty-finish warning was
a `confirmationDialog` reading "tap the circle at the end of each row" while
sitting on top of those rows. It is now a card in the page under "Log Your
Sets", it does not block anything, and it clears itself when a set is logged —
otherwise the page insists nothing is logged directly above a row that plainly
is. Prefer an in-page notice to a dialog for anything that is a hint rather
than a decision.

**Done on that summary is load-bearing.** The summary hides the navigation bar
(`visualPhase == .recover`), so there is no back button behind it. Removing
Done would leave the screen with no exit; show the navigation bar first if it
ever needs to go.

### The three-day-old bug

Adding a conditional constraint changed the contract, which was not obvious:
**drf-spectacular emits the default of any field a constraint's `condition`
names.** `kind` gained `default: task`, the generator turned it into a payload
wrapper, and create and patch each got their own nested `KindPayload`. The app
would not have compiled against its own backend without regenerating and
following through. Diff the schema after any model change, not only after a
serializer change.

## August 19: Apple Health

Steps, and workouts imported from what the iPhone or Watch already recorded.
Read-only, always: everything Repbase can record it records itself, and
writing back would give one workout two homes and no way to say which is
right.

### Two checks that looked like failures and were not

The entitlement was committed on its own, with nothing calling it, so a build
could test the foundation before a feature rested on it. Two of the four
checks came back wrong, and both were the check's fault:

- `codesign -d --entitlements` on the `.app` prints an **empty dict**. That is
  the *device* slot, empty because there is no provisioning profile. The
  simulator reads `IOS Frontend.app-Simulated.xcent`, where the entitlement is
  present.
- `otool -L` on the executable shows **no HealthKit**. Xcode 16 debug builds
  put the app's code in `IOS Frontend.debug.dylib`; the framework is linked
  there and the main binary is a stub.

Neither proves anything about runtime. The check that does: launch with
`REPBASE_HEALTH_CHECK=1` and screenshot. A missing entitlement makes
`requestAuthorization` fail immediately with an error and no sheet; a working
one shows Apple's sheet and waits — a difference a script can see even though
the sheet needs a tap no script can give. **The sheet appeared.**

### What a paid membership would still buy

Device builds. Xcode strips `com.apple.developer.healthkit` from
`IOS Frontend.app.xcent` because no profile authorises it, so a device build
will not sign until the App ID carries the HealthKit capability. The simulator
does not enforce provisioning, which is the only reason this works at all.
There is also no Apple Watch in the simulator, so real Watch data needs both a
membership and a device.

`NSHealthUpdateUsageDescription` is **not** required for a read-only app; it
was removed and the app still launches and reads. Apple's sheet says "access
and update your Health data" either way — that header is Apple's boilerplate,
not something the plist controls. The part that reflects the actual request
reads "Allow to read" and lists only Steps.

### Two ways to count steps, one of them wrong

Health stores the phone's steps and the watch's steps as **separate samples**.
Summing samples double-counts every day someone wore both.
`HKStatisticsCollectionQuery` with `.cumulativeSum` de-duplicates by source
and buckets by day in one pass. That is the only reason the number is right.

A day with no samples is **left out**, never sent as zero: "nobody walked" and
"Health was never asked" are different, and only one of them is a fact. Days
are formatted in the device's own calendar, never UTC — at 9pm in California a
UTC date is already tomorrow, and the evening walk would be filed under a day
that has not happened.

Steps are displayed from the **server**, not from Health. The device sends
what Health reported and then draws what came back, so the count on Home is
the count every client would see.

### Import decides on the server

The device sends every Health workout in a 30-day window; the server says what
it did with each. Deciding on the device would mean downloading the training
history first, and the answer would still be the server's to give.

Two guards, and they are not the same guard:

- **Health's own identifier** is stored on the session, so re-sending a
  workout finds the row it already made.
- **Overlap with a session Repbase recorded itself** is skipped. The app's own
  recording wins: it has the route and the barometric climb the imported one
  lacks. Only self-recorded sessions are compared against, so two imported
  workouts that abut do not cancel each other out, and the comparison is
  half-open, so a workout starting exactly when a session ends is imported
  rather than dropped.

Both were exercised against the real database rather than read: overlapping
skipped, clear ones imported, an identical second batch recognised as already
imported, an abutting import not skipped, and the probe user removed in a
`finally`. Worth repeating that shape of test for anything whose whole value
is a decision rule.

The skip is **reported**, not silent — three counts come back, because
"nothing was added" has three causes. Dropping a duplicate quietly would read
as the import missing workouts rather than declining to double-count.

Imported sessions attach to a workout named for the activity, created on first
use, so they land in the history the app already draws rather than needing a
kind of session no screen can render.

### Only four activities

Running, cycling, swimming, and traditional or functional strength training
map onto Repbase's four types. Everything else in Health returns nil and stays
there. A tennis match has no row this app can draw, and inventing a type for
it would put something in the training history that nothing can explain.

### Asking is Apple's job, not the page's

The card first offered a "Connect Apple Health" button, and an explanation
when Health had not answered. Both were prompts on the screen, and the user
wanted neither: **the app requests Health access itself, once, and the only
thing shown is Apple's own sheet.** The card renders only when there are steps
to draw — no permission state, no empty state, no error text. A Home page that
explains why a feature is quiet is louder than one that simply is.

HealthKit shows its sheet once per app install and does nothing on later
calls, so asking automatically cannot become nagging. Two consequences when
testing: installing **over** an existing build will not show the sheet again,
and `simctl uninstall` resets it. Uninstalling does **not** sign the user out —
the token is in the Keychain, which lives outside the app container.

### One trap worth knowing

`record` first returned the stored rows. drf-spectacular, seeing a paginated
viewset, described that as a pagination envelope while the action actually
returned a bare array — the generated client would have failed to decode every
sync. The Swift compiler caught it as a type error. It now answers **204**:
nothing needed the echo, because the store re-reads through `list` anyway.

### The 404 that was not in the app

Steps came back `HTTP 404` in the running app while every route was correctly
declared. The dev server runs `--noreload` and was still serving code from
ninety minutes earlier; the restart had been written as
`launchctl kickstart ... | head -2 || pkill ...`, and a pipeline's exit status
is the last command's, so `head` succeeding hid `kickstart` failing.

The first diagnosis was wrong too. `/api/v1/sessions/import-health/` answered
`401`, which looked like proof the route existed — but the router matches it as
`sessions/{pk}/` with `pk` of `import-health` and rejects on auth before ever
resolving the pk. **Probe a path the router cannot mistake for a detail route.**
`restart-devserver.sh` in the backend repo now does the restart and the check
together, and fails loudly on 404.

## August 19: miles, and gear

### The app reads imperial and stores metric

Every distance, pace, speed and climb now reads in miles, mph, seconds per
mile and feet. **Nothing about storage changed.** The server computes and keeps
kilometres and metres, and conversion happens in `ImperialUnits` at the edge
where a number becomes a string. Putting the unit into the database would mean
every stored figure had to be read alongside whichever preference was in force
when it was written.

Two conversions that are easy to get backwards:

- **Pace inverts.** A mile is longer than a kilometre, so seconds per mile is
  the *larger* number. Getting it the wrong way makes a 5:00/km run into a
  3:07/mi one, which is a world record rather than a Tuesday.
- **Convert once.** `SessionProgressChart` converts its plotted points, so the
  caption underneath must not convert the difference again — that would report
  a mile of improvement as 0.62. Anything reading `points` is already imperial.

Inputs convert the other way, at the same edge: what is typed in miles becomes
kilometres before it is sent. That applies to the cardio distance box and to
both mileage fields in the gear editor.

Splits had to move too. The server cut them at kilometre boundaries, and a
split measured in one unit but labelled in another describes a run nobody did,
so `MILE_KM` is the boundary now. That renamed the field `kilometer` →
`number`; `distance_km` still reports kilometres, so a full split reads 1.609.

### Gear

A shoe or bike is its own record, not a label on a session, because a shoe
outlives any one run and the question worth answering is how much is left in
it. Attaching gear to a running or biking session adds that session's distance
to its total.

**Mileage is summed on the server**, over every session the gear was attached
to, plus whatever distance it arrived with. That last part matters: a shoe
added half way through its life would otherwise claim to be new.

This needed `WorkoutSession.recorded_distance_km`. `route_distance_km`
recomputes from the stored track every time it is read — fine for one session,
impossible to sum in SQL across the hundred a shoe was worn for. It is written
once, when a track is uploaded or a workout is imported from Health.

The picker appears **twice**, in the live session and again on the summary,
because it is one decision reached two ways and forgetting beforehand should
not be permanent. A default per kind is preselected; a single shoe is used
without being marked default, since choosing between one thing is not a choice.

**The wear bar only appears when the user states where the end is.** The
obvious thing is to assume shoes last 500 miles and warn at 400, but that is a
guess about somebody else's shoes presented as a measurement of theirs.

Rules the server enforces, all verified against the database rather than read:
a bike cannot be attached to a run, gear belonging to someone else is refused,
retired gear is refused, retiring keeps every mile and drops it from the list,
and detaching a session gives its distance back.

### Two failures worth not repeating

**An edit that matched nothing, silently.** `gear` was supposed to join the
session serializer's field list and did not — a `perl -0777 -pe s///` that
matched no text exits 0 and prints nothing. The contract shipped without it and
only the Swift compiler noticed. Now these scripts read the result back and
print it.

**Inserting at a text marker without looking at what precedes it.** A python
insert placed a method immediately before `def get_logged_set_count`, which sat
under an `@extend_schema_field(serializers.IntegerField())` decorator. The
decorator was orphaned onto the new method, `logged_set_count` fell back to
`string` in the contract, and every client would have failed to decode it.
Check for a decorator above any line you insert before.

## August 20: rotations, for splits that are not a week long

An eight-day split does not land on a weekday. It falls on Monday, then
Tuesday, then Wednesday, and keeps drifting. `WorkoutRecurrence` is a rule
about a weekday and structurally cannot say this, so rotations are a separate
thing rather than an option on the existing one.

A rotation is a **length** and an **anchor date**. Everything else follows:
the day of the cycle is `(days since anchor) mod length`, and shifting the
whole plan is a matter of moving the anchor by a day. That is the reason it
is anchored to a date at all — a weekly rule could only be "shifted" by
becoming a rule about a different weekday, which is not the same thing.

Rest days are slots. A six-workout two-rest split is an **eight**-day
rotation, not a six-day one; leaving the rest days out makes it land wrong
from the second turn onwards.

### The two ways back on schedule

They are different questions and both are needed.

| Control | What it does | When |
| --- | --- | --- |
| **I rested today** | `POST cycles/{id}/shift/ {days: 1}` — pushes everything still to come back a day | One unplanned rest day, order kept |
| **Resume today** | `POST cycles/{id}/resume-today/` — re-anchors so the workout that is owed lands today | Several days missed, no wish to count them |

Both **replace** the rotation rather than editing it: the old one is closed
with `effective_until` and a new one starts. That is why the store re-reads
after a shift instead of patching in place, and why the old rule is kept
rather than deleted — weeks already trained still have to resolve through
whatever was planned at the time.

Neither disturbs a day something already happened on. `_materialize` uses
`get_or_create`, and the shift leaves days with a session, or added by hand,
where they are — the response counts them as `kept`, and the screen says so.
A plan quietly rearranging itself is unsettling; one that reports "6 days
rescheduled, 1 left alone" is not.

### The UI

`CycleView` is reached from a row at the bottom of the Workout plan card,
the same doorway pattern gear uses. The row shows **Day 3 of 8** and today's
workout when a rotation is running, and a one-line offer when none is. Every
number on it comes from the server; the app does no cycle arithmetic.

`CycleEditorView` lists days 1..N in cycle order, because that is the
template being defined. `CycleView` lists them **starting from today**,
because that is a schedule. This is not cosmetic: in cycle order the dates
run backwards partway down — on day 3 of 8, day 1 is six days out while day 4
is tomorrow — and the header's "next: Push on Sat" then contradicts the first
Push in the list. Fixed in `4f29f44` after a screenshot showed it.

`REPBASE_CYCLE_PREVIEW` boots straight in: unset value or `1` for a running
rotation, `empty` for the no-rotation state, `editor` for the editor,
`dashboard` for the doorway row in place. The editor needs a saved library
behind it, so the preview injects `WorkoutStore.previewWithLibrary`;
`WorkoutStore.preview` alone leaves it showing nothing but "save a workout
first".

### A rest slot had no name

`workout_name` was `CharField(source="workout.name", read_only=True)`. On a
rest slot that chain hits `None`, and DRF answers a missing attribute on a
non-required field by **dropping the field entirely** — not by sending null.
The contract meanwhile marked it `required` and non-nullable, so the key was
absent from a response that promised it, and the Swift client would have
thrown `keyNotFound` on **any rotation containing a rest day**. Which is
every eight-day split worth having.

It is now a `SerializerMethodField` returning `"Rest"`, matching what
`current_workout_name` already did. Fixed in backend `28f481c`.

Worth generalising: a read-only field whose `source` traverses a nullable
relation will silently vanish rather than serialise as null. `grep` for
`source="` with a dot in it before trusting any such field to be present.

### The backend's "today" is UTC

`TIME_ZONE = 'UTC'` with `USE_TZ = True`, so `timezone.localdate()` is the
**UTC** date. For a user in US Central that rolls over at **7pm local**: at
8pm on Thursday the rotation already reports Friday's workout, and
`_materialize` starts writing from the wrong day.

This is not a rotation bug — every date-keyed feature has it, food days and
streaks included — but rotations are where it shows most, because "which day
of the cycle am I on" is the entire promise. It was found by a probe
disagreeing with a simulator screenshot about what day it was, not by
reasoning.

Not fixed here. It is a cross-cutting decision: changing `TIME_ZONE` shifts
the meaning of dates already stored, so it needs a deliberate choice about
what a "day" means for this app — most likely a per-user timezone on the
profile, with `localdate()` calls replaced by one helper that reads it.

## August 21: the feed becomes social, and four traps

Two sessions worked the same tree all day. Most of what follows is one
session's; where a commit message does not match its contents, that is why —
`git add -A` picked up the other's work in progress more than once. Stage
explicit paths.

### Likes, comments, reposts, saving

A post could be made and read and nothing else. Now:

- **Likes** are a row per like, not a counter. Unliking is a delete, two taps
  in a second cannot both increment, and the count is exactly who is in the
  table.
- **Comments** nest one level. A reply to a reply is refused rather than
  quietly re-parented, so a thread stays a comment and the replies under it.
- **A repost is a `Post`** with `repost_of` set and a fourth `kind`, so it
  inherits the feed ordering, the visibility rules and the cursor paging
  instead of needing a second model all three would have to learn. Reposting
  a repost passes on the original.
- **save-workout** copies a posted workout's exercises and set counts into
  the reader's own workouts — a plan to follow, not a record of somebody
  else's session, so no weights. Names are unique per user, so a copy of a
  "Push Day" you already have arrives as "Push Day (from @them)".
- **Weights are optional at post time.** Withholding happens at *snapshot*
  time: the numbers are never written, rather than written and filtered on
  every read. That matches how a post already works — it freezes a copy so
  editing last week cannot rewrite what people have read. The cost is that
  changing your mind means reposting.

Counts are correlated subqueries, not `Count` over joins. Three aggregates
pulled through three multi-valued relations multiply out: a post with four
likes and three comments reports twelve of each.

### Four traps, all of which cost a build or more

**A `.task` inside a `TimelineView` may never run.** The feed and several
other screens rebuild once a minute for the time-of-day palette. Anything
attached inside that closure is torn down and re-declared on every tick. A
`navigationDestination` there never pushed — tapping a post did nothing while
liking one worked, because liking needs no navigation. A `.task` there never
fetched. **Attach navigation and loading to `body`, outside the
`TimelineView`.**

**The bottom bar is drawn over pushed screens, not inset out of them.** It is
a `safeAreaInset` on the `TabView`, so the keyboard lifts it and it lands on
anything pinned to the bottom. The comment box sat underneath it, invisible.
Scrolling pages pad by `RepbaseDesign.bottomBarClearance`; a pinned control
has to as well. A screen can also ask the bar away entirely with
`hidesBottomBar(_:)` — a preference the shell reads — which is what the
comment box does while it is being written in.

**Inserting a class above `class Foo` can steal its decorator.** Anchoring on
the `class` line put a new view between `PostViewSet` and its
`@extend_schema_view`, which then applied to the new view. `CreatePostRequest`,
`VisibilityEnum`, `CreatePostKindEnum` and `PatchedUpdatePostRequest` all
vanished from the contract and the client stopped compiling. Anchor *above
the decorator*. This is the second time in two days — see the
`logged_set_count` note.

**A serializer field sourced through a nullable relation vanishes.** Covered
under the rotation section; it bit again here. `SerializerMethodField` is the
safe form when the source can be null.

### Cancelled is not failed

`NSURLErrorDomain Code=-999` means the app cancelled its own request, which
SwiftUI does whenever a `.task`'s view goes away or its id changes. It
arrives at a `catch` looking exactly like a server being down, and 56 sites
across eight stores were putting it on screen with a Retry button for work
the app had deliberately abandoned. `Error.userFacingMessage` returns nil for
a cancellation; every store reports through it. The check walks
`NSUnderlyingErrorKey`, because the generated client buries the URLSession
error under its own.

### Photos

Post photos are two to four megabytes. `AsyncImage` caches nothing, so every
rebuild restarted the download — once a minute, forever, inside the feed's
`TimelineView` — and decoded at full size on the main thread for a box 200
points tall. That is why a picture appeared on a post's own page, which draws
one, and not in a feed drawing several. `RemoteImage` fetches once per URL and
decodes at the size drawn. A failure now draws a placeholder: nothing at all
is indistinguishable from a post that never had a picture.

Server-side thumbnails would be the better fix and do not exist yet.

### Two things worth knowing about the data

There are **two Aaron accounts**: `AARONPIO` (RepbaseUser 5, no posts, no
follows, stale) and `aaron.pio` (RepbaseUser 59, the live one). Querying the
wrong one made a working follow look broken. Check `user__username`.

**Discover lists 77 accounts**, nearly all `*_probe_*` users left by test
scripts from several sessions. Worth a cleanup; they make the tab useless for
judging the real thing.

### Prev: on the set fields

The hint existed and had never once appeared. The client found it by reading
recent sessions of the same workout until one turned out to have logged
something, giving up after five — and the account's last **nine** Push Days
had been started and abandoned, with the session holding the numbers tenth.
Raising the number moves the cliff and costs a round trip per attempt.
`GET /api/v1/sessions/previous-sets/` answers it in one query, per exercise,
so an exercise that moves between workouts keeps its history.

### The step goal

`8_000` was hardcoded in two places and shown as a label nobody could change.
It is `RepbaseUser.daily_step_goal` now, beside target weight, so it follows
the account rather than the phone. Bounded 1,000–100,000 server-side, and the
sheet's stepper uses the same bounds so it cannot compose a refused request.

### The dev server fights itself

`restart-devserver.sh` used to `pkill` the server and start its own with
`nohup`. The server belongs to the **launchd agent `com.repbase.devserver`**,
which has `KeepAlive`, so that started a race: both fought for port 5000, the
loser retried forever, and because it redirected with `>` it truncated the
shared log on every attempt — which is how the traceback behind a 500 went
missing. While both were briefly alive they were two writers on one SQLite
file, which reaches the app as an HTTP 500.

A `nohup` server is reparented to pid 1 when its shell exits, so it looks
exactly like a launchd child in `ps`. **`launchctl list` is what tells them
apart**: a dash in the PID column means the agent's own job is not running and
something else holds its port. The script now unloads the agent, clears any
stray, loads it again, and refuses to report success while more than one
server is alive.

### Launch flags added this session

`simctl` still cannot tap, and a preview harness renders a screen on a bare
stack with no tab bar — which is not the layout anyone gets, and is how a
comment box that could not be reached shipped twice. These open the **real
signed-in app**:

| Flag | Opens |
| --- | --- |
| `REPBASE_TAB=social\|training\|planner\|account\|home` | that tab |
| `REPBASE_SOCIAL_OPEN=<post id>` | that post's page, pushed through the feed |
| `REPBASE_SOCIAL_COMMENT=<post id>` | the comments sheet over the feed |
| `REPBASE_SOCIAL_FOCUS=1` | arrives mid-comment, keyboard up |
| `REPBASE_SOCIAL_SEND=<text>` | types a comment and sends it |
| `REPBASE_SOCIAL_PREVIEW=feed\|detail\|push` | sample data, no account needed |
| `REPBASE_CYCLE_PREVIEW=1\|empty\|editor\|dashboard` | the rotation screens |

`REPBASE_SOCIAL_SEND` writes a real comment. Delete it afterwards.

### Build before pushing

Three commits reached `main` this session that did not compile — a missing
`return` on a multi-statement view body, a modifier on a bare `if/else`, and
`CLLocationManager.authorizationStatus` without its parentheses. Each blocked
every later commit from reaching the simulator until someone noticed.

Nothing gates a push on a build. Until something does, **build before you
commit, not after** — and when verifying an install, check the clone's SHA
*and* that it is not dirty, not only that the installed binary matches the
build product. A blocked merge leaves the clone a commit behind while that
MD5 check still passes.

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

Added August 18–19, all additive:

```text
Post.image                              base64 in, image_url out
CreatePostRequest.content_type,         carried on the create, not uploaded
                  image_base64          afterwards
GET  /api/v1/exercises/?name=           exact, case- and space-insensitive
GET  /api/v1/session-exercises/?session= existed, was never declared
GET  /api/v1/set-entries/?session=       one session's sets in one request
     /api/v1/set-entries/?session_exercise=  existed, was never declared
WorkoutSession.logged_set_count         annotated on the list query
WorkoutSchedule.planner_synced_at       internal; not serialized
POST /api/v1/schedules/sync-planner/    {start, end} -> the tasks it created
PlannerEntry: unique_workout_task_per_day, conditional on kind=task

DailyStepCount                          day (date), steps; one row per user
                                        per day, unique together
GET  /api/v1/step-counts/?since=        days on or after a date
POST /api/v1/step-counts/record/        {days:[{day, steps}]} -> 204,
                                        replacing any day sent again
WorkoutSession.health_external_id       Health's own id; unique per user
                                        when set
WorkoutSession.health_distance_km       distance as Health reported it,
                                        not derived from a GPS route
POST /api/v1/sessions/import-health/    {workouts:[...]} -> {imported,
                                        skipped_overlapping, already_imported}

Gear                                    kind (shoe|bike), name, brand, notes,
                                        initial_distance_km, retire_at_km,
                                        is_default, retired_at; read-only
                                        total_distance_km, session_count
GET  /api/v1/gear/?kind=&include_retired=
POST/PATCH/DELETE /api/v1/gear/       retiring is a PATCH of retired_at
WorkoutSession.gear                     writable; refused when the kind does
                                        not suit the sport
WorkoutSession.recorded_distance_km     read-only; what gear mileage sums
SessionSplit.kilometer -> number        splits are cut at miles now
```

Regenerate the client on macOS after any contract change:

```bash
bash Scripts/generate-api-client.sh
```

Never hand-edit `API/GeneratedSources`. Two contract mismatches were caught by
the compiler this session and are worth remembering:

- A custom `@action` returning `Response(serializer.data)` is **not** paginated,
  but `drf-spectacular` documents `many=True` as a paged envelope when the view
  has a paginator. Set `pagination_class=None` on the action, or return `204`
  and let the caller re-read through `list`. **This was written down and then
  walked into again** on the step-count endpoint, so read this list before
  adding an action, not after the compiler complains.
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

1. **Nothing gates a push on a build.** Three commits reached `main` on
   August 21 that did not compile, each blocking every later one from
   reaching the simulator. A pre-push hook running the Mac build would end
   this; nobody has added one.
2. **The social features are barely tapped.** Verified against the database
   and rendered in the real signed-in app, and a comment has been sent by
   hand end to end. Untouched by a human: **Save workout**, the weights
   toggle at post time, reposting, deleting a comment, and Discover's search
   box.
3. **Two Aaron accounts and 77 probe users** are in the development database.
   `aaron.pio` (RepbaseUser 59) is the live one; `AARONPIO` (5) is stale.
   The probe accounts fill Discover and make it useless for judging.
4. **Post photos are served at full size.** Two to four megabytes each, with
   the client shrinking them after download. Server-side thumbnails are the
   real fix and do not exist.
1. **The backend's day is the UTC day.** `TIME_ZONE = 'UTC'`, so for a user
   west of it the date rolls over before their evening is out — 7pm for US
   Central. Rotations show it worst ("Day 3 of 8" advances early), but every
   date-keyed feature shares it. See the August 20 section; the fix is a
   per-user timezone, not a change to the global setting.
2. **Nobody has tapped the rotation screens.** Built, installed, launched and
   screenshotted in all four `REPBASE_CYCLE_PREVIEW` states, and the rules
   underneath are exercised against the database by `/tmp/test_cycles.py`
   (drift across weekdays, a shift sparing a trained day and a hand-added one,
   the weekly-repeat clash refused). But no human has created a rotation,
   pressed **I rested today**, or edited one.
1. **Repeats are new and have not been used across a real week boundary.** The
   logic is verified against the API (see below), but nobody has yet opened the
   app on a Monday and watched the week fill in. That is the one thing worth
   checking first.
2. **Most UI is still verified by compiling, not by tapping.** `simctl` has no
   tap, swipe or scroll command, so an agent can build, install, launch and
   screenshot, and nothing more. Say which of those you did. GPS and the
   barometer need a real device besides.

   What *has* been exercised by hand, as of August 19: posting with a photo
   (a 4 MB image posted and served back), the previous-set hints, a completed
   session and its overview. What has not: **Redo Session, Undo, the calendar
   entry's Share, the empty-finish notice, and — as of August 19 — the
   Connect Apple Health button — since removed; Apple's sheet now appears on
   its own; and every part of **gear**: adding a shoe, picking one for a
   session, retiring one. The gear screens have only been seen with the
   `REPBASE_GEAR_PREVIEW` sample data behind them; the rules underneath were
   exercised against the database, but nobody has pressed any of the buttons.** The empty-finish notice came off this list the hard way: it was
   blocking **every run, ride and swim** from being finished at all. Its guard
   fired on `loggedSetCount == 0`, which a distance workout always is, and the
   notice explaining the refusal is only drawn on the lifting layout, so both
   buttons did nothing and said nothing. A guard and the thing that explains it
   must be behind the same condition. The sheet has been seen and photographed appearing automatically
   on a fresh install, but nobody has pressed Allow, so no real steps or
   workouts have ever made the round trip; the widget has only been seen with
   sample days behind it. Every UI defect found this
   session was in something on that second list, and each was found by the
   user rather than by a build — a dead tick, a modal covering its own
   subject, a task that would not sync. Assume the remaining five have the
   same shape of problem until somebody taps them.

   Two tricks that get further than a screenshot of the first screen. The
   `REPBASE_*_PREVIEW` flags boot straight into a screen that is otherwise
   only reachable by tapping — `REPBASE_HEALTH_PREVIEW=widget` goes further and
   draws one card alone, because on Home that card runs below the fold and no
   script can scroll to the rest of it. `REPBASE_ROUTE_PREVIEW=1` draws the
   finished-run map on a canned track, and `=empty` draws the no-track state,
   which is the one a simulator session actually produces: it cannot move, so
   every run recorded there has no route — **relaunch without the flag afterwards**, or the
   user is left looking at a one-page app full of sample data. And an **iPad**
   simulator often fits a whole scrolling page in one screenshot; but a page
   that does not overflow an iPad is not evidence about scrolling on a phone,
   which is a claim that was nearly made here.
3. **Food is on the server** as of `a71e7f4`; this document said otherwise for
   days after it stopped being true. Almost nothing is stored on the device:
   the auth token in the Keychain, and — as of August 19 — a single
   UserDefaults flag, `repbase.health.hasAsked`. No SwiftData, no files. That
   flag exists because HealthKit will not report whether a read was allowed;
   saying so would leak that someone declined, which is itself health
   information. It records having asked, not the answer. Verified by grep on
   August 18 and corrected on August 19, because the claim in this document
   had already outlived the code once. Vitamins and micronutrients remain
   **unavailable** rather than invented: the OAS still has no nutrition
   analysis, and the breakdown is computed on the phone from the meal in hand.
4. **No XCTest target and no CI.** The only validation gate is an Xcode simulator
   build on the Mac plus manual review. Given how many real bugs surfaced this
   session through scripted API probes, a test target would be worth real money.
5. The OAS declares no stable error schemas, so failure messaging stays generic.
6. Schedule uniqueness and timezone behaviour remain contract gaps.
7. `db.sqlite3.backup-before-workout-type` is intentionally untracked in the
   backend repo. Preserve it. `ROADMAP.md` **is** tracked in the iOS repo,
   whatever this document said before.
8. **The backend repo has 15 `.pyc` files tracked** in
   `core/migrations/__pycache__/`, committed before `.gitignore` covered them.
   They are compiled for CPython 3.12 while the Mac runs 3.14, so Python
   ignores them. Harmless, and `git rm -r --cached` whenever someone wants the
   noise gone.
9. **The bottom bar is inset on the `TabView`**, outside each tab's navigation
   stack, so its height never reaches the scroll views inside. Every scrolling
   page inside a tab must leave `RepbaseDesign.bottomBarClearance` at the
   bottom — including pages *pushed* onto a tab, which is the half that was
   missed the first time. Sheets and full-screen covers must not: they cover
   the bar rather than sit under it.
10. The dev database contains probe accounts created while verifying
   (`claude_*`, `pr_*`, `hist_*`, `name_*`, and similar) and some implausible
   test data — Pullups logged at 300 kg × 12, which suppresses genuine PRs on
   that exercise.

## Expected working style

- Read `git status` before editing and preserve unrelated changes. The user has
  edited files in parallel this session; changes were silently reverted twice
  before their in-progress work was committed. **Stage your own files by name.**
  `git add -A` swept another session's in-progress work into three commits on
  August 18.
- Verify claims rather than asserting them. Scripted API probes against the live
  backend caught several real bugs this session that reading code did not:
  a vanishing final split, absurd average speeds, phantom elevation on flat
  ground, and a kilometre of distance from a stationary phone.
- **Reading code is not verifying it.** `retirePastDue` was read, judged
  correct, and reported as working; it had never once run, because the bug was
  in the caller one line above. A screenshot from the user diagnosed it. When a
  user says a feature does not work, believe the screenshot over the code.
- **Check the data before blaming the code, and after changing it.** "The hints
  do not show" was three completed sessions holding zero sets, not a bug. The
  planner duplicate count in the database is what proved that fix, not the build
  log.
- **`manage.py check` does not execute a serializer body.** Two `NameError`s
  shipped past it this session — `profile_for` not importable in
  `serializers.py` (it lives in `views.py`; importing it makes the two import
  each other), and a serializer missing from the import list in `views.py`.
  Exercise the path with an `APIRequestFactory` probe.
- **Beware the shape of your own test harness.** A retry loop wrapped around
  `grep -c` — which exits non-zero on zero matches — relaunched the app eight
  times and signed the user out, then the missing requests looked like a broken
  feature. Two other false alarms came from checking the backend port once,
  immediately after restarting it.
- Prefer editing by exact anchored text. Deleting by line number cascaded and
  mangled `MealDetailView` mid-session; a brace-balance check caught it and a
  backup taken beforehand made it cheap to undo.
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
