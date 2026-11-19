# Real local workout testing

This uses the actual iOS app and a real local API/database, not a sample-data
preview. It does not deploy the testing branch to `rytivo.app`. Keep the two
repositories on their working testing branches; main and TestFlight stay unchanged.

## First-time Mac setup

Open two Terminal tabs. The examples assume the repositories are in `~/Documents`.
If you cloned them elsewhere, change only the `cd` paths.

In Terminal 1, clone the backend if you do not already have a local copy:

```bash
cd ~/Documents
git clone --branch work/testflight-calendar-sync-2026-10-28 https://github.com/P-B-LLC/repbase.git
```

Then prepare and start the local backend. Python 3.14 matches the project's CI
and pinned dependencies. Check `python3 --version` before creating the environment.

```bash
cd ~/Documents/repbase
git status --short
git fetch origin
git switch work/testflight-calendar-sync-2026-10-28
git pull --ff-only
python3 -m venv .venv-local-workout
.venv-local-workout/bin/python -m pip install -r requirements.txt
.venv-local-workout/bin/python Scripts/run-local-workout-testing.py
```

If `git status` shows your own edits, preserve them before switching/pulling;
do not reset or discard them. The first start asks you to choose a **new local
password** for `local_workout_tester`. It is not displayed or saved in plaintext.
Never enter your live Rytivo credentials. Leave Terminal 1 open while testing.

In Terminal 2:

```bash
cd ~/Documents/IOS-Frontend
git status --short
git fetch origin
git switch work/testflight-fixes-2026-10-27
git pull --ff-only
bash Scripts/run-local-workout-simulator.sh
```

The script checks the local backend identity and per-set support, builds Debug,
verifies the bundled loopback origin, and opens a dedicated **Rytivo Local Workout
Testing** simulator. Sign in as `local_workout_tester` using the separate password
you chose. Review the agreements normally on first sign-in. No preview launch
flag is set and no simulator containing a live account is reused or erased.

## Restart later

Terminal 1:

```bash
cd ~/Documents/repbase
.venv-local-workout/bin/python Scripts/run-local-workout-testing.py
```

Terminal 2:

```bash
cd ~/Documents/IOS-Frontend
bash Scripts/run-local-workout-simulator.sh
```

The backend retains `.local-workout-testing/db.sqlite3` and local media. It
does not reseed or reset your workouts or password. Ctrl-C stops the server
without deleting that database. The dedicated simulator is retained too.
If port 8765 is busy, the backend refuses to start instead of using another
server. Choose matching alternatives explicitly:

```bash
# Terminal 1
.venv-local-workout/bin/python Scripts/run-local-workout-testing.py --port 8766
# Terminal 2
RYTIVO_LOCAL_PORT=8766 bash Scripts/run-local-workout-simulator.sh
```

## Verify a real save, not just a screenshot

1. Create a workout with at least two exercises and different reps/weights
   for each planned set. Save it, leave the editor, and reopen the saved plan.
2. Confirm the order and every target match. Close the app and stop/restart
   the local backend; reopen the plan and confirm the values still match.
3. Start that workout and check each set's target. Log one set with different
   actual results; confirm the planned target and actual result stay distinct.
4. Change kg/lb on one active exercise. Its neighbour's unit and entered values
   must remain unchanged. Relaunch and confirm active-session recovery.
5. Test add/remove/copy-first, warm-up/drop kinds, zero-weight/bodyweight sets,
   empty optional targets and validation feedback. Cancel an edit and verify
   the stored plan was not changed. Check light/dark and larger text.

## Boundaries and evidence

- The launcher passes a clean environment, reads no `.env`, and uses only its
  marked database/media directory. No SMTP, Redis, APNs, moderation provider,
  hosted database, background worker or live deployment credentials are used.
- The server listens on `127.0.0.1` and also rejects non-loopback requests.
  The app uses its existing explicit DEBUG loopback HTTP allowance. Release
  HTTPS enforcement and App Transport Security are unchanged.
- This SQLite setup verifies real request/save/reload behavior, but is not a
  PostgreSQL concurrency test or evidence of a production deployment.
- `run-e2e-ui-tests.sh` remains a separate throwaway automated suite. Its seed
  deletes/recreates test data; **do not run that seed against this durable DB**.
- The isolated `WorkoutFlowUITests` previews test view interaction but cannot
  prove backend persistence. Actual local/API and PostgreSQL tests are separate.
- The previous `d2ff53f` CI candidate passed both builds, 525 regression tests,
  and both native unit-control tests. Its two drag-position tests failed;
  do not describe all native workout-flow checks as passing.
