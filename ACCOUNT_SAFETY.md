# Account safety implementation and verification

## Implemented

- Offline, timeout, server, and decoding failures keep the saved Keychain credential and show a retry screen. Only an explicit 401 rejects the restored session; account content is not unlocked until restoration succeeds.
- Logout tears down local state before waiting for the remote logout request. A credential-removal marker prevents a failed Keychain deletion from silently restoring the account on a subsequent launch. This marker contains no credential.
- Account deletion uses the same local cleanup once the server confirms deletion.
- Cleanup stops GPS/barometer updates and clears route samples, live totals, workout summaries/history, stores, cached photos, and cached URL responses.
- Account-owned reminders and delivered notifications are removed on logout. In-flight scheduling uses a generation identifier and uniquely named requests; stale writes remove their own request rather than removing a new account's reminder. Notification actions are checked against the active account.
- Delayed auth/workout responses cannot overwrite a newer account generation. App startup checks the active token between store connections, and Health connection work checks its generation before continuing.

## Automated checks

`bash Scripts/test-account-safety.sh` on macOS builds a temporary Swift package using the actual authentication, configuration, and Keychain source files. It uses an in-memory credential store and injected restore responses, never a real account or server.

The XCTest cases cover:

- offline/timeout/500/decoding/403 errors retaining credentials;
- 401 rejection clearing credentials and invoking cleanup;
- retry without re-entering a password;
- logout while an older restore response is pending;
- failed Keychain deletion across app instances.

The runner is included in the existing macOS CI workflow. These native tests and the iOS build were **not executed on this Windows implementation host**. Passing source checks is not a replacement for compiling and running them.

## Required device checks before beta sign-off

1. Launch offline after a successful sign-in; retry online and confirm no password entry is needed.
2. Revoke a test token server-side and verify the next restore requests login.
3. Start GPS tracking, then sign out/delete the account; confirm the location indicator stops and all live figures clear.
4. Schedule reminders, log out, then switch accounts while deliberately slowing requests; no old task details, photos, history, or notifications should appear.
5. Toggle notification preferences and mute actions; verify reminders still work after relaunching the same account.
6. Test remote logout failure, Keychain access failure, and account deletion in the signed Release build.
7. Run the Swift test script and Xcode build on macOS, including light/dark recovery-screen visibility and large text.

## Backend dependency

The companion backend contains migration `0048_pendingmediadeletion` and a retry command. Follow its `ACCOUNT_SAFETY.md` before deploying. No release deployment or Git push was performed by this implementation task.

This completes the account-safety implementation batch, not overall beta certification. Other audit work, native validation, and the production release checklist remain.
