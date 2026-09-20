# Push notifications: pre-deployment validation checkpoint

Community activity now has an APNs registration coordinator, opt-out sync,
account-checked tap routing, cold-launch inbox loading and foreground filtering.
Workout/meal/planner reminders still use the existing local scheduler. The APNs
signing key is server-side only; no key was added to this repository.

## Required on the Mac

The Mac's SSH connection is blocked. The user successfully completed the Mac
validation script and reported a successful simulator build/launch. The generated
client was committed and verified on GitHub as `59ab18a`; it is no longer stale.
The commands below remain available to repeat validation after further changes.

From the repository, with the desired simulator booted:

```bash
git pull --ff-only
bash Scripts/validate-push-notifications.sh
```

The script generates API sources, runs account-safety tests, builds a signed
simulator app, and installs/launches it if a simulator is booted. It preserves
its unique temporary build directory. If Git reports local changes, preserve
and inspect them instead of resetting the project file.

If a future generation run changes the client, review and commit that diff:

```bash
git diff --stat -- API/GeneratedSources
git add API/GeneratedSources
git commit -m "Regenerate API client for push device registration"
git push
```

## Real delivery gate

The backend implementation must be deployed/migrated and its worker enabled
separately; it remains unchanged on the droplet at this checkpoint. Until then,
registration may display its retryable sync error because the endpoint is not
deployed. See backend `deploy/PUSH_NOTIFICATIONS.md` before activation.

- Debug: development entitlement + sandbox registration. The current production
  key cannot deliver to this environment.
- Release/TestFlight: production entitlement + production registration. Verify
  the exported application's signed `aps-environment` is production, and that
  Push Notifications is enabled for `com.pbllc.rytivo` in Apple Developer.
- A Release build development-signed directly onto a phone must override both
  `APNS_ENTITLEMENT_ENVIRONMENT=development` and `APNS_SERVER_ENVIRONMENT=sandbox`.
  Build configuration and the actual provisioning environment must match.

Use two beta test accounts: allow alerts, background the receiver, then follow
or comment from the other account. Confirm one alert and a cold-launch tap into
the inbox. Repeat with community alerts off, iOS permission denied, a blocked
actor, logout and account switching. Test offline preference changes: show the
sync error, reconnect and retry, then verify the new preference server-side.

An offline logout cannot immediately revoke the server's token; the app warns
about possible continued generic alerts. Already accepted APNs alerts cannot be
recalled. Payloads contain generic text and account/routing IDs, not usernames,
messages, meals, health data or photos. Never promise exactly-once delivery.

Do not treat simulator success as a passing TestFlight/APNs test. Signed physical
device delivery is still outstanding. Backend deployment is blocked by the
existing `core.E006` moderation gate: the user confirmed no automated moderation
provider API key has been obtained yet. The Apple APNs key is a separate
credential and does not satisfy this requirement. Do not bypass the gate.

Backend follow-up: all 56 targeted PostgreSQL tests passed with no skips,
including both push concurrency tests. The isolated test cluster was stopped;
production remains unchanged. See backend `deploy/PUSH_NOTIFICATIONS.md` for
the verified commit, reproducible test script and deployment blocker.
