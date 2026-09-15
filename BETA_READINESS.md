# Beta readiness

Audit item 4: stale food-day refresh protection is implemented; see
[food synchronization verification](FOOD_DAY_SYNC_GATE.md) for scope and tests.

September 13 follow-up: audit fixes 1–3 (default gear, partial photo posts,
social likes) are implemented. See [implementation and verification notes](BETA_AUDIT_FIXES_1_3.md).
Remaining production and verification gates below are not automatically closed.

What stands between today's `main` and a real person using Rytivo. Written
2026-09-12, revised 2026-09-13 after a full audit. Covers both repositories;
`repbase` items are marked.

Everything below was checked against a running build or server, not read off
the source. Where something is inferred rather than observed, it says so.

---

## Blockers

A beta tester hits these on day one. Roughly in dependency order: 1 and 3 both
need the host that 4 produces, so 4 is the one to start, and 6 is the one to
start *today* because it is the only item with somebody else's queue in front
of it.

### 1. Give release builds a server URL

**State:** the plumbing works, the value is not set. A Release build today has
the key present and **empty**, and exits immediately on launch:

```
key present, value = []  (len 0)
still running: 0
```

`APIConfiguration` requires an `https` URL and calls `preconditionFailure`
without one. That is deliberate — far better than a build quietly talking to a
laptop — but it means an unset value is a crash, not a warning.

**Do:** define `REPBASE_API_URL` for the Release configuration once the host in
item 4 exists — an `.xcconfig`, a build setting, or a CI-injected value. It
must be `https`.

**Careful:** CI's "release build carries the server it was given" step passes
its own dummy URL. It proves the key still reaches the bundle; it does **not**
prove a real one is configured. Green CI is not evidence this item is done.

**Verify:**
```bash
xcodebuild -project "IOS Frontend/IOS Frontend.xcodeproj" -scheme "IOS Frontend" \
  -configuration Release -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/dd CODE_SIGNING_ALLOWED=NO build
/usr/libexec/PlistBuddy -c "Print :REPBASE_API_URL" \
  "/tmp/dd/Build/Products/Release-iphonesimulator/Rytivo.app/Info.plist"
```
Then install it and confirm it is still running ten seconds later. A build that
launches and vanishes is this bug.

### 2. Serve media with `DEBUG` off — *done, `a98ad5f`*

Photos are served by `core/media.py` in every configuration, behind a keyed
signature, and no longer under `if settings.DEBUG`. Against a `DEBUG=False`
server: signed 200, unsigned 403, tampered 403. The real app needed no change
— its requests appear in the access log carrying signatures, answered 200.

The same commit closed the access-control gap below. What is left here is a
**deployment choice, not a code change**: set `REPBASE_MEDIA_ACCEL_REDIRECT_ROOT`
to the internal location a proxy maps onto `MEDIA_ROOT` and nginx sends the
file while Django only checks the signature — no image bytes through Python.
Left unset it works, just with Python pushing the bytes.

Object storage (S3/R2 + `django-storages`) remains the long-term answer and is
now a settings-level change: everything reads through `default_storage` rather
than the filesystem, which was worth getting right — the first version called
`django.views.static.serve` and would have worked perfectly until media moved
to S3 and then served nothing.

### 3. Configure email — *repbase* — *code done `f936138`, account not bought*

**Was:** no provider, so `send_mail(..., fail_silently=False)` raised and a
password reset returned 500 with a live code already written — and that 500
only ever happened for an address that *has* an account, which made a mail
outage into the account enumerator the blanket 204 exists to prevent.

**Now:** a failed send spends the code and still answers 204, with the failure
logged. And the bad configuration cannot reach production quietly:
`manage.py check --deploy` refuses Django's `localhost` SMTP default, a
`DEFAULT_FROM_EMAIL` on a reserved suffix, and SMTP without TLS. Verified —
with the defaults this repository shipped it reports exactly `core.E002` and
`core.E003`, and with a provider configured it reports neither.

**Left to do, and it needs a person with a card:** pick a provider (Postmark,
SES, Resend, Fastmail — anything that will relay), and set `SMTP_HOST`,
`SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` and `DEFAULT_FROM_EMAIL` on a
domain that exists. Then request a reset against a `DEBUG=False` server and
read the mail. Until the domain in item 4 exists there is nothing to put in
`DEFAULT_FROM_EMAIL`, so this follows the deploy rather than leading it.

### 4. Deploy the backend at all — *repbase*

**State:** there is no deployment. SQLite, `manage.py runserver` (single
threaded, documented as not for production), bound to `127.0.0.1` on a shared
MacinCloud box, no `Dockerfile`/`Procfile`/`fly.toml`. A phone on cellular
cannot reach it.

**Do:**
- Postgres. `config/test_postgres.py` exists, so that move is already started.
- A host with HTTPS, and `DJANGO_ALLOWED_HOSTS`, `DJANGO_SECRET_KEY` and
  `DJANGO_DEBUG=false` set. The security settings already read from env and
  tighten themselves when `DEBUG` is off — that part is done.
- Run `manage.py check --deploy` as part of starting it, and treat a failure
  as a failed deploy. That is what makes item 3's checks worth having.
- Decide what happens to today's data: **10 accounts, a 2 MB database and
  21 MB of media** on the Mac. Migrate or start clean, but decide rather than
  discover.
- A real WSGI/ASGI server (gunicorn/uvicorn), not `runserver`.
- **A daily scheduler**, for `manage.py prune_expired_rows` (expired food-cache
  entries and save receipts) and `manage.py retry_media_deletions` (storage
  deletions that failed after their row was gone). Both are safe to run twice,
  on an empty database, and interrupted. Until something runs them, two tables
  that now have an expiry policy still never actually shrink.

### 5. Turn on branch protection — *ruleset committed `ca93235`/`8415cf4`*

**State:** both repos run CI on every push and pull request, and nothing
depends on the result. That is how `18487ff` — which did not compile — reached
`main` and sat there for a week.

**Do:** Settings → Rules → Rulesets → New ruleset → **Import a ruleset**, and
pick `.github/rulesets/protect-main.json` from that repository. Once each. The
two files differ because the job lists do.

Be ready for what it costs: a required check cannot have passed for a commit
that is not on GitHub yet, so direct pushes to `main` stop working and the
flow becomes branch → push → pull request → merge. Details in
[RELEASING.md](RELEASING.md).

### 6. Buy an Apple Developer membership

**State:** not bought. `DEVELOPMENT_TEAM` appears zero times in the project,
there is no distribution certificate and no App Store Connect record, so there
is no way to put a build on a phone that is not plugged into this Mac.

**Do:** [APPLE_DEVELOPER.md](APPLE_DEVELOPER.md) is the ordered list. The one
thing worth starting today is the **D-U-N-S lookup**, if the LLC rather than a
person should be the seller: it is free, it can take five business days, it
gates the enrolment, and it cannot be changed afterwards without transferring
the account. Everything else on that list takes minutes, and everything the
repository can do in advance — bundle name, entitlements, privacy manifest,
export-compliance declaration, archive and export script — is done.

---
## Carry these into the database move

From an audit on 2026-09-13, run against the live database and a built app
rather than by reading. Everything here is invisible on SQLite with ten
accounts and stops being invisible somewhere between there and a real
PostgreSQL with real people on it. Four items from that audit are already
fixed and are recorded below so nobody re-finds them.

### Fixed

- ~~**The PostgreSQL job ran two test modules.**~~ *Fixed, `c4868c5`.* It ran
  the two written for the row-lock work — the tests least in need of a real
  database, because they were written knowing they needed one. It now runs the
  whole suite. **This has never executed**: the build Mac has no PostgreSQL and
  no container runtime, which is exactly why the gap existed. The first Actions
  run is the real test, and a failure there is the job working.
- ~~**A new database connection per request.**~~ *Fixed, `c4868c5`.*
  `CONN_MAX_AGE` is 60 seconds with health checks. Read the comment before
  deploying behind PgBouncer in transaction mode — there it must be 0.
- ~~**Every launch re-downloaded every photo.**~~ *Fixed, `b920553`.* The
  decoded-image `NSCache` dies with the process and `URLSession.shared` had the
  system default response cache, a few megabytes. The signed media URLs already
  round their expiry to a whole day so they stay cacheable, and the responses
  already carry `immutable` — none of which bought anything until there was
  somewhere to put the bytes that outlives a launch.
- ~~**The image cache bounded a count, not a size.**~~ *Fixed, `b920553`.*
  Images are charged their decoded bytes against a 64 MB ceiling.

- ~~**Two tables that only ever grew.**~~ *Fixed, `prune_expired_rows`.*
  `FoodSearchCache` was the largest table in the database — 53 KB from about
  ten development accounts, ahead of every table holding real user data — and
  `SaveReceipt` was the same shape and brand new. Both now expire, and both
  have an index on the column the pruning query reads.

  The trap worth knowing about: the food cache has **two clocks, deliberately
  far apart**. `LIFETIME` (7 days) decides when an answer is re-fetched;
  `RETENTION` (90 days) decides when the row is deleted. Past `LIFETIME` an
  entry is stale but not useless — it is exactly what the search endpoint
  serves when FoodData Central cannot be reached. Pruning on `LIFETIME` looks
  right and quietly deletes the outage fallback, and nothing would say so
  until an outage. Two tests fail if anyone makes that change.

  `SaveReceipt` expires the **payload**, not the key, which is a correction to
  the first version of this: deleting the row after thirty days let a late
  retry create a duplicate, and a phone holds an uncertain save in a file
  indefinitely, so the late retry is exactly the one that has been waiting.
  The row now becomes a compact 409 saying the save happened and its replay
  answer is gone. Rows live until the account is deleted — small, and still
  refusing to create anything twice.

  **This needs a scheduler**, which is part of blocker 4 above. Until
  something runs the command daily, "expires" still means "would expire".

- ~~**Unindexed, unenforced account identity.**~~ *Fixed, `3b27f52`.* Sign-in,
  registration and password reset all matched on `__iexact` with no expression
  index anywhere in the schema, so every one of them scanned the user table on
  PostgreSQL; and case-insensitive uniqueness was a serializer check followed
  by a commit, which SQLite hides by allowing one writer at a time. One unique
  index on the upper-cased column answers both, for email and username.

  Raw SQL, because the model is `django.contrib.auth`'s and this project
  cannot add a migration to that app. The email index is **partial** — two
  accounts in the live data have no email at all, and an empty string is not a
  duplicate of another empty string. That was found by running the migration
  against the real database rather than only an empty test one; a non-partial
  index would have refused to apply.

- ~~**The session list walked every GPS track it returned.**~~ *Fixed,
  `377fd11`.* The decision was between a lighter serializer for list responses
  and storing the derived values, and the app settled it: `sessionHistory`
  reads distance, pace, moving pace and elevation gain **off the list
  endpoint** to plot progress for a named workout, so dropping them would have
  broken a shipped feature. The list keeps reporting them and stops
  recomputing them instead — seven values worked out when the track is
  uploaded and kept in one JSON column, with computing left in as the fallback.

  Safe because the upload endpoint is the only thing in the codebase that ever
  writes `SessionRoutePoint`, so a stored summary cannot drift from the points
  it describes. Contract unchanged — the schema output is byte-identical, so
  the generated client needed nothing.

  Worth knowing for the next performance fix here: **a query count would not
  have caught this.** `prefetch_related` is one query however many sessions
  there are, so the unfixed code satisfied "more sessions, same number of
  queries" while pulling every fix of every session into memory. The cost was
  rows and arithmetic, not round trips, and the test asserts the point table is
  not read at all.

### Still open

Nothing here that does not need the deployed database or the Apple account.
The two items above that are marked fixed but not yet *running* — pruning needs
a scheduler, and the PostgreSQL job has never executed — are the ones to watch
when the host exists.

---

## Should do before strangers use it

- ~~**Media has no access control.**~~ *Done, `a98ad5f`.* A photo URL now
  carries an HMAC over the file name and an expiry, so it is unguessable and
  stops working on its own — roughly a week, rounded to a day so the URL stays
  stable long enough for the app's image cache to be worth having. It does not
  decide *who* may see a post; that is still the feed's job, done where the
  post is served, so someone who cannot see a post never receives its URL.
  What it bounds is how long a URL keeps working once handed out.
- ~~**`CFBundleName` is "IOS Frontend".**~~ *Done, `0f56899`.* Both the
  display name and the bundle name are Rytivo, and CI reads the latter back
  out of a built Release app rather than trusting the build setting.
- **`LegalDocuments.contactEmail` is `support@repbase.app`**, and the privacy
  copy tells users to write there to have data removed. If nobody reads that
  mailbox, the legal text promises something no one answers.
- **Documentation has outgrown anyone reading it.** 3,100 lines across
  seventeen files between the two repositories, of which `CLAUDE_HANDOFF.md`
  is 1,526 on its own. `SAVE_RECOVERY.md` exists in *both* repositories
  describing one feature from two sides, alongside `WORKOUT_SAVE_GATE.md`,
  `PLANNER_COMPLETION_GATE.md` and an `ACCOUNT_SAFETY.md` that is also in
  both — five documents for one area of work. The gate documents were written
  to be read once, by whoever took the next shift, and that has happened.
- **Backups.** Nothing is backed up today. Once a stranger's data is in there,
  losing it is a different kind of problem.
- ~~**Build numbers.**~~ *Handled, `0defe8a`.*
  `Scripts/archive-for-testflight.sh` numbers each build with the commit
  count, which only goes up, and refuses to export an archive carrying a
  different number than it asked for.

---

## Where the test net has holes

Worth knowing before trusting a green run:

- **No XCUITest target.** The project has one product, the app. Nothing can tap
  anything, so no test covers a gesture, a transition, or a screen appearing.
  `Scripts/test-account-safety.sh` is a SwiftPM package that copies individual
  source files in; it only reaches files that compile alone.
- **That package is not built with the app's `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor`,** so actor-isolation errors pass there and fail the app target.
  That is exactly how `18487ff` got through.
- **Navigation routing is covered by unit tests only.** `RepbaseRoute` encodes
  the rules and seven tests check them, but no test taps a Home card.
- **The release-gate workflows have never executed.** The YAML parses; GitHub
  Actions has not run it. The first `v*` tag is the real test.
- ~~**Route tracking has never stored a single point.**~~ *Run, `5e48257`.* It
  has now: 20 fixes recorded from simulated GPS, uploaded through the real
  repository method, stored, summarised (0.057 km, 10.8 km/h top speed, 19.1
  moving seconds, one split) and decoded by the app. `RouteProbeView` does what
  the tap would have led to — `simctl privacy grant` supplies the
  authorisation, `simctl location start` drives the waypoints — following the
  `HealthKitProbeView` pattern already here for the same kind of problem.

  **It found a bug on the first run**, which is the argument for having done
  it: the upload returned 200, the server stored every point, and the app
  could not decode the reply. `workout_name` was omitted rather than sent as
  null for a session with no template, and since `workout` is `SET_NULL`,
  deleting one workout template made every session that used it undecodable —
  a training history that stops loading. Fixed in `03af2c6`.

  **Still unrun: altitude.** `simctl` supplies no barometric data, so
  `elevation_gain_m` came back nil and that path has still never executed.
  And none of this replaces someone recording a real run outdoors with the
  screen locked — background location, signal loss and battery are all
  untouched by it.
- ~~**The PostgreSQL job has never executed.**~~ *Run, 2026-09-15.* It runs the
  whole suite on PostgreSQL 17 and passes: **339 tests, zero skipped**, against
  339 with three skipped on SQLite. Those three are the row-lock concurrency
  tests, which skip themselves on any other database — zero skips is what says
  they finally ran for real.
- ~~**iOS CI had never built the app.**~~ *Fixed, `87a5991`.* Worth recording
  because it was invisible for a month: the workflow selected Xcode by exact
  path, the runner image stopped shipping that path, and `xcode-select` failed
  as the first step of every run. Each later step was skipped and the run went
  red — which reads like the code being broken, so nobody looked past the
  verdict. **Thirty consecutive runs compiled nothing.** It now picks the
  newest Xcode present and fails on the version, naming what it found.

  The reason this mattered more than a red badge: the branch-protection ruleset
  requires the `build` check, and that check had never once passed. Importing
  the ruleset before this fix would have blocked every merge.
- **The photo-test teardown fix was never reproduced.** The failure is a
  Windows file-handle case; the suite is clean on macOS, CI is Linux, and there
  is no Python on the Windows checkout. It was fixed by reading the code.

---

## Deliberately deferred

**`PhotoCropperView` still does full-resolution work on the main thread** — the
upright copy in `init`, and the JPEG encode in `croppedData` when Use is
tapped. Moving it needs the button to hold a busy state so it cannot be tapped
twice, which changes behaviour in a view whose gesture handling was recently
hard to get right, and `simctl` cannot tap to check the result. The feed decode
— the one that ran for every photo on every scroll — is already off the main
thread and measured.
