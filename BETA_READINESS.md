# Beta readiness

What stands between today's `main` and a real person using Rytivo. Written
2026-09-12. Covers both repositories; `repbase` items are marked.

Everything below was checked against a running build or server, not read off
the source. Where something is inferred rather than observed, it says so.

---

## Blockers

A beta tester hits these on day one. Roughly in dependency order — 1 needs the
host that 4 produces, so 4 is the one to start.

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
  "/tmp/dd/Build/Products/Release-iphonesimulator/IOS Frontend.app/Info.plist"
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

### 3. Configure email — *repbase*

**State:** no `EMAIL_BACKEND` is set, so Django falls back to SMTP on
`localhost:25`. `core/views.py` calls `send_mail(..., fail_silently=False)`, so
a password reset request raises and returns 500. The reset code row is written
*before* the send, so the user ends up with a code that was never delivered.

`DEFAULT_FROM_EMAIL` also defaults to `noreply@repbase.local`. `.local` is a
reserved mDNS TLD — undeliverable, and most providers reject it as a From
address.

**Do:** set a real provider (`EMAIL_BACKEND`, host, port, credentials) and a
`DEFAULT_FROM_EMAIL` on a domain that exists. Decide whether a send failure
should still 500 or be swallowed with the code invalidated; 500 is defensible,
silently pretending is not.

**Verify:** request a reset against a `DEBUG=False` server and read the mail.

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
- Decide what happens to today's data: **10 accounts, a 2 MB database and
  21 MB of media** on the Mac. Migrate or start clean, but decide rather than
  discover.
- A real WSGI/ASGI server (gunicorn/uvicorn), not `runserver`.

### 5. Turn on branch protection

**State:** both repos run CI on every push and pull request, and nothing
depends on the result. That is how `18487ff` — which did not compile — reached
`main` and sat there for a week.

**Do:** the exact clicks are in [RELEASING.md](RELEASING.md). It is a
repository setting, not a file, so no commit can do it.

---

## Should do before strangers use it

- ~~**Media has no access control.**~~ *Done, `a98ad5f`.* A photo URL now
  carries an HMAC over the file name and an expiry, so it is unguessable and
  stops working on its own — roughly a week, rounded to a day so the URL stays
  stable long enough for the app's image cache to be worth having. It does not
  decide *who* may see a post; that is still the feed's job, done where the
  post is served, so someone who cannot see a post never receives its URL.
  What it bounds is how long a URL keeps working once handed out.
- **`CFBundleName` is "IOS Frontend".** The display name is correctly Rytivo,
  but the bundle name shows in parts of system UI and in App Store Connect.
  `PRODUCT_NAME = "$(TARGET_NAME)"` is where it comes from.
- **`LegalDocuments.contactEmail` is `support@repbase.app`**, and the privacy
  copy tells users to write there to have data removed. If nobody reads that
  mailbox, the legal text promises something no one answers.
- **Backups.** Nothing is backed up today. Once a stranger's data is in there,
  losing it is a different kind of problem.
- **Build numbers.** Currently `1.0 (1)`; every TestFlight upload needs a new
  `CFBundleVersion`.

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
