# Beta readiness

Audit item 4: stale food-day refresh protection is implemented; see
[write-ordering gates](GATES.md) for scope and tests.

September 13 follow-up: audit fixes 1–3 (default gear, partial photo posts,
social likes) are implemented. See [implementation and verification notes](BETA_AUDIT_FIXES_1_3.md).
Remaining production and verification gates below are not automatically closed.

What stands between today's `main` and a real person using Rytivo. Written
2026-09-12, revised 2026-09-13 and again 2026-09-16 after a full audit. Covers
both repositories; `repbase` items are marked.

Everything below was checked against a running build or server, not read off
the source. Where something is inferred rather than observed, it says so.

---

## Blockers

A beta tester hits these on day one. Roughly in dependency order: 1, 3 and 7
all need the host that 4 produces, so **4 is the one to start**. Nothing here
now has somebody else's queue in front of it — the D-U-N-S wait that used to
make item 6 urgent is gone, and what is left of that item is clicking rather
than waiting.

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

### 5. Turn on branch protection — *done 2026-09-16*

**Was:** both repos ran CI on every push and pull request, and nothing depended
on the result. That is how `18487ff` — which did not compile — reached `main`
and sat there for a week.

Both rulesets are now imported and enforcing. Confirmed by asking GitHub what
applies to `main` rather than by reading the create response:

| repo | required checks | also |
|---|---|---|
| `repbase` | `test`, `postgres` | no deletion, no force-push |
| `IOS-Frontend` | `build` | no deletion, no force-push |

`bypass_actors` is empty in both, so the rules apply to everyone including the
owner. The required contexts were checked against the names GitHub actually
records on a finished run — `test`, `postgres`, `build` — because a context
that never matches is not protection, it is a branch nobody can ever merge to.

A required check cannot have passed for a commit that is not on GitHub yet, so
**direct pushes to `main` no longer work**; the flow is branch → push → pull
request → merge. Details in [RELEASING.md](RELEASING.md).

Note this became possible on `repbase` only when it was made public on
2026-09-16. Rulesets are not available for private repositories on the free
plan — the API answered *"Upgrade to GitHub Pro or make this repository
public"* until then.

### 6. Apple Developer membership — *bought and signed in 2026-09-16*

**Was:** not bought, and the D-U-N-S lookup in front of it was the longest
queue in the whole beta. That is gone.

**State:** bought, and the build Mac is signed in to it. From Xcode's own
preferences on that machine, 2026-09-16: a paid team
(`isFreeProvisioningTeam = 0`, so not a personal one), `teamType = Individual`,
and zero provisioning profiles — consistent with nothing having been built for
a device yet. Selecting the team in Xcode wrote `DEVELOPMENT_TEAM` into
`project.pbxproj`, which is committed.

**Do not check this with `security find-identity` over SSH.** It answers
"0 valid identities found" on a machine that is signed in perfectly well,
because the login keychain refuses to open without a GUI session —
`SecKeychainCopySettings: User interaction is not allowed`. An earlier
revision of this document recorded that zero as evidence the account was not
set up. It was evidence of nothing. Xcode's preference domain is readable over
SSH and is where the answer actually is:

```bash
defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier
```

**Do**, from [APPLE_DEVELOPER.md](APPLE_DEVELOPER.md):

- Register the App ID `com.pbllc.rytivo` — character for character with
  `PRODUCT_BUNDLE_IDENTIFIER` — and **enable HealthKit on it**. The
  entitlements file asks for HealthKit and a device build refuses to sign
  without it. The simulator does not enforce provisioning, which is why no
  build here has ever caught this.
- Create the App Store Connect record.
- Then archive. **On your own Mac, not the hosted one** — see below.

```bash
DEVELOPMENT_TEAM=ABCDE12345 REPBASE_API_URL=https://api.example.com/ \
  ALLOW_PROVISIONING_UPDATES=true \
  bash Scripts/archive-for-testflight.sh
```

Example values, not `<placeholders>`: `<` and `>` are shell redirection
operators, so pasting `https://<host>/` dies with `bash: host: No such file or
directory` before the script runs at all.

`ALLOW_PROVISIONING_UPDATES` is off by default and needed only the first time:
without it xcodebuild says `No profiles for 'com.pbllc.rytivo' were found` and
stops, which is the right default because issuing a certificate changes the
developer account. With it, Apple issues an Apple Distribution certificate and
an App Store profile.

**Where that runs decides where the signing key lives.** The certificate's
private key stays in the login keychain of whichever machine asked for it, and
the hosted build Mac is administered by somebody else. Decided 2026-09-16:
archive from a personal machine, and leave the hosted Mac for CI, which needs
no signing at all. Verified on the hosted Mac that everything up to signing
works there — team resolves, the build runs, and it stops exactly at the
missing profile — so nothing about that choice is guesswork.

**Decided, and not reversible:** the enrolment is `teamType = Individual`, so
the App Store seller name will be the individual's legal name rather than
P&B LLC. Apple does not let this be flipped — it is an account transfer. The
bundle identifier, the GitHub organisation and the company name all say the
LLC, so this is worth confirming as intended *before* the App Store Connect
record exists, because that record is where the seller becomes a published
fact. Nothing in the legal documents names an entity either way, so nothing
there contradicts it.

**The Team ID is committed**, in `project.pbxproj` as `DEVELOPMENT_TEAM`, put
there by Xcode when the team was selected. An earlier revision of this document
said the repository deliberately did not store it. That was true when nobody
had opened the project with an account attached, and it stopped being true the
moment somebody did — keeping it out would have meant re-selecting the team on
every fresh checkout, to protect a value Apple embeds in every distributed
binary and that is readable from any `.ipa`.

`Scripts/archive-for-testflight.sh` still takes `DEVELOPMENT_TEAM` as an
environment variable and refuses to run without one, which is what lets
somebody archive under a different team without editing the project.

**Worth knowing:** the build Mac is a shared hosted machine. An Apple account
signed in there, and the signing identity it installs, live on hardware
somebody else administers. That is a decision to make deliberately rather than
by default.

### 7. Configure moderation — *repbase* — *code done, nothing configured*

**State:** the code is finished and enforcing; the configuration does not
exist, and it **blocks deployment outright**. `check --deploy` against
`config.production` fails:

```
?: (core.E006) Production social publishing requires configured automated
   moderation.
   HINT: Configure MODERATION_API_KEY and enable moderation. Do not bypass
   it to ship.
```

That is an `ERROR`, and `config.deploy` runs `check --fail-level ERROR`, so
this is not a warning to get to later — the deploy stops here. Observed, not
inferred: the same command passes once the four values below are set.

**Do**, all on the host from item 4:

- **`MODERATION_API_KEY`** — an OpenAI key, in secret storage, never in Git.
  Without it every submission fails *closed* with 503, so an unset key is not
  "moderation off", it is "publishing off".
- **`MODERATION_DISCLOSURE_CONFIRMED=true`** — an operator assertion that the
  published privacy policy says content goes to OpenAI. It does: the wording
  is in `LegalDocuments.swift` and in `Legal/privacy.html`, and the two were
  confirmed in sync on 2026-09-16. Set it only once that page is served from a
  public URL.
- **`MODERATION_CONSENT_VERSION`** — must equal the app's
  `ModerationDisclosure.version`, today `2026-09-15`. **These two move
  together or every submission 403s.** Bumping the server's value is how an
  older build is cut off after the wording changes; bumping it by accident is
  how a shipped build is cut off for nothing.
- **A mailbox at `support@rytivo.app`** — the appeal address the refusal text
  hands people. Shared with the item in *Should do before strangers use it*
  below, and blocking here for the same reason: a refusal that names an
  address nobody reads is worse than no address.

`MODERATION_ENABLED` needs no attention — it defaults false for development
and `config/production.py` forces it true, which is why nothing is checked
against a local `runserver` no matter what else is set.

**Verify** (2026-09-16, against a running server): with moderation enabled and
the disclosure flag still false, every one of the nine moderated endpoints —
register, profile update, profile photo, prompts, social links, gym create,
comment create, post update, post create — answered **403
`moderation_consent_required`** without the consent header and **503
`moderation_unavailable`** with it. That ordering is the useful test: it
reaches the consent gate without contacting the provider, so it can be re-run
on any host without sending anyone's content anywhere. Anything answering 403
*with* the header is the serializer-context bug, and it would refuse every
real user.

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
- **`support@rytivo.app` does not exist yet, and four things now promise it
  does.** It is the privacy contact for data deletion, the address for
  reporting a child's account, the moderation appeal route, and the App Review
  privacy contact. It replaced a personal Gmail — which was at least a mailbox
  somebody read, so until this one exists the product is *less* reachable, not
  more. Create it, confirm mail arrives, and confirm somebody is actually
  watching it before a stranger is invited in; App Review checks that a privacy
  contact works. This is also part of blocker 7 above: it is the address a
  moderation refusal tells people to appeal to.
- **Documentation is still long, though no longer duplicated.** The four
  write-ordering gate documents are now one [GATES.md](GATES.md), keeping what
  the code and tests cannot say — what each guarantees and what nobody has
  verified — and dropping the build narration `git log` holds better.
  `CLAUDE_HANDOFF.md` is still 1,526 lines, read at the start of every session,
  and is deliberately left alone: other sessions treat it as the handoff
  contract, and gutting it unilaterally would break them rather than help.
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
