# Connected workouts — testing only

## Scope and status

This candidate lives on `work/testflight-fixes-2026-10-27` and requires the
backend `work/testflight-calendar-sync-2026-10-28` with migration
`0094_health_workout_summaries`. Main, the live backend and TestFlight are not
changed. Check the exact candidate's CI result before promotion. Compilation,
automated tests and genuine watch-to-phone delivery are separate gates.

Open **Training → Connected apps** or **Settings → Connected apps**.
Apple Watch uses the iPhone's read-only Apple Health store; this is not a new
watchOS app, a live heart-rate monitor or a write-back connection.

### Apple Health

- Explicit account-and-device opt-in explains what is uploaded, then requests
  Apple's permission sheet. Signing into another account never implicitly
  uploads the device owner's Health data.
- Steps and completed workouts are read in bounded windows: seven days of
  steps and thirty days of workouts. Workouts are queried in pages and sent
  in batches of at most 100. Foreground refresh is throttled; explicit retry
  remains available.
- Time, source, specific sport, distance, active energy and average/maximum
  heart rate are stored when provided. No raw heart-rate series or Health GPS
  route is uploaded. Missing data stays missing, not zero. Calorie readings
  are device-reported estimates, not a claim of clinical accuracy.
- Private readback powers expandable workout cards and workout history,
  including strength sessions without sets. Imports refresh the shared
  workout state; native logs and manual/GPS measurements are retained.
- A stable source ID prevents duplicate imports. A conservative match can
  enrich an existing same-activity session; ambiguous overlaps are skipped
  and reported, not silently attached to an arbitrary workout.
- Pause stops device uploads immediately. A failed server pause is retained
  for retry. Previously imported workouts remain; OS permissions are managed
  separately in Health. Sign-out clears visible account data; account deletion
  clears its local consent preferences as well.
- Health read denial cannot be distinguished from an empty store. The UI says
  **Sync enabled**, not **permission granted**. Read/network failures never
  advance the device's successful-sync timestamp.

### Garmin

The owner has not yet obtained Garmin Connect Developer Program approval.
Direct Garmin OAuth, webhooks, historical backfill and write-back are **not
enabled**. The dashboard exposes this limitation instead of a pretend Connect
button. Source-labelled **Garmin via Apple Health** summaries can appear when
Garmin Connect actually writes them into Health and the user enables import.
No Garmin password, API secret or access token belongs in the iOS app.

Official sources checked on 2026-11-12:

- [Garmin program tiers and approval](https://developer.garmin.com/gc-developer-program/overview/)
- [Activity API: completed workouts after device sync](https://developer.garmin.com/gc-developer-program/enterprise/activity-api/)
- [Training API: planned workout delivery](https://developer.garmin.com/gc-developer-program/enterprise/training-api/)
- [Garmin → Apple Health setup and limitations](https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA)
- [Apple Health authorization and read privacy](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)

After approval, confirm the granted scopes, signed/verified notification
contract, payload/deletion semantics, token lifecycle and capacity limits in
Garmin's portal before implementing the direct adapter. Planned workout
delivery is not evidence that completed activities can be edited in Garmin.

## Run the real testing app

Use the separate local backend and simulator described in
[WORKOUT_LOCAL_TESTING.md](WORKOUT_LOCAL_TESTING.md). Pull both testing branches,
restart the local backend so migrations run, and launch:

```sh
cd ~/Documents/IOS-Frontend
git switch work/testflight-fixes-2026-10-27
git pull --ff-only
bash Scripts/run-local-workout-simulator.sh
```

This uses real API requests and separate test accounts, not preview fixtures.
It does not deploy to rytivo.app. An old backend shows an update-required state
and does not accept the new Health connection. Use the full Xcode developer
directory if Simulator is unavailable; do not delete existing simulators.

## Validation checklist before activation

Backend candidate `0951d05` passed its 1,740-test suite on both SQLite and
PostgreSQL, schema freshness, production configuration and dependency audit:
[backend CI](https://github.com/P-B-LLC/repbase/actions/runs/43363526529).
The new Apple Health suite includes two PostgreSQL-only locking cases.
The iOS candidate requires its own Mac result; the prior branch had an
unresolved workout-reorder edge-autoscroll UI test. Do not treat an individual
build/test step as a green full workflow or proof of physical watch delivery.

1. Connect explicitly; deny or allow only some types. Empty data must not be
   described as proof that permission was granted or refused.
2. Import a run, a walk and a Watch strength workout. Inspect actual available
   metrics, source labels and history, including no-set strength workouts.
3. Repeat sync and retry after a lost response. One workout remains one record;
   delayed metrics enrich it without erasing existing readings.
4. Match a native workout conservatively; verify its sets, notes, GPS and
   manually entered values remain intact. Ambiguous overlap must be reported.
5. Switch accounts during reads and uploads. No data or stale success message
   may appear for the next account. Connect each account separately.
6. Pause while offline, reopen and retry. Uploads stay off locally until an
   explicit new connection. Confirm server state when connectivity returns.
7. Test pagination, missing/invalid metrics, inaccessible Health data while
   locked, large backfill, offline readback and revoked access.
8. Inspect light/dark, large text, VoiceOver and all supported languages.
9. On a physical iPhone paired to Apple Watch, finish and sync real permitted
   workouts. Use a separately authorized HTTPS testing backend; the loopback
   simulator backend is not reachable from the phone. Simulator success is
   not hardware synchronization validation.
10. With Garmin hardware, enable Garmin Connect's Health sharing, sync in
    Garmin Connect, then sync Rytivo. Confirm actual source identifiers and
    missing metrics. Do not label this a direct Garmin API connection.

No automatic deletion reconciliation with Health is claimed. Removing a source
sample does not silently erase a Rytivo workout or its training logs. Direct
Garmin ingestion and cross-provider reconciliation remain gated follow-up work.
