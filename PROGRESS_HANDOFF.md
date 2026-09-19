# Progress checkpoint — 2026-09-19

User requested a stopping point with all changes committed and pushed.

## Repository state

- Frontend branch: `fix/calendar-subtask-dropdown`, tracking the same branch on origin.
- Feature commit: `0978437` (active lifting widget and Live Activity).
- Earlier commits: `05aea46` calendar subtasks, `d945da2` Home Screen widgets,
  `06f029c` Widget initializer fix, `9ee56c5` planner pagination.
- These features are NOT merged into main. Main requires the build status check;
  do not bypass branch protection. No PR was created during this work.
- Backend: `repbase` main at `d37b457`, clean and matching origin at checkpoint.
  No backend changes were required for these widgets.

## Implemented

- Calendar Anytime parents use the existing expandable subtask checklist.
  Server-confirmed subtask completion completes/reopens the parent.
- My Day, Workout, Food, and Planner Home Screen widgets; shared App Group
  snapshot, stale-day handling, logout cleanup, and tap-to-open navigation.
- Planner Previous/Next controls and range labels; small/medium/large layouts
  show 1/2/7 items per page. Same-size widget instances share page position.
- Active lifting widget plus Lock Screen/Dynamic Island Live Activity:
  elapsed timer, kg/reps controls, existing set-save path, next unfinished set,
  duplicate/stale-tap guards, and explicit review/finish in the app.
- Read `WIDGETS.md` for setup, lifecycle limitations, and outstanding checks.

## Validation and Mac workflow

The user reported successful simulator builds and that the widgets work,
including the latest active-workout implementation. These are user-reported
results, not an agent-run device test suite. Unit tests have been added but
have not been executed by this agent. Background/cold-start, network failure,
duplicate logging, logout, and physical-device/TestFlight checks remain open.

Mac SSH at `user299988@216.14.167.87` accepts the public key then closes during
authentication. The user has no sudo or system-log access. Do not regenerate
keys or loosen SSH permissions as a guess; provider/admin investigation is needed.

Mac checkout: `~/Documents/IOS-Frontend`. A local Xcode project-file change was
stashed with message `Mac Xcode settings before active workout update`. The
visible diff was formatting/comments, and filtered signing values matched.
The complete stash was not inspected. Preserve it; do not drop/pop blindly.

Simulator widget builds MUST use signing. The earlier unsigned build installed
without App Group containers, leaving every widget in its placeholder state.
The user confirmed the signed rebuild restored planner data.

```bash
cd ~/Documents/IOS-Frontend
git switch fix/calendar-subtask-dropdown
git pull --ff-only
xcrun simctl bootstatus booted -b
xcodebuild \
  -project "IOS Frontend/IOS Frontend.xcodeproj" \
  -scheme "IOS Frontend" -configuration Release \
  -destination "platform=iOS Simulator,id=$(xcrun simctl getenv booted SIMULATOR_UDID)" \
  -derivedDataPath /tmp/rytivo-widgets-signed \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  REPBASE_API_URL=https://rytivo.app build
```

Install only after a successful build:
`xcrun simctl install booted /tmp/rytivo-widgets-signed/Build/Products/Release-iphonesimulator/Rytivo.app`

Launch: `xcrun simctl launch --terminate-running-process booted com.pbllc.rytivo`

This configuration uses the live backend. Never mutate real records as automated
test fixtures. Run `bash Scripts/test-account-safety.sh` on a working Mac for the
added unit tests. Signed device profiles need shared group `group.com.pbllc.rytivo`
on both `com.pbllc.rytivo` and `com.pbllc.rytivo.widgets`.

## Infrastructure / push notifications

DigitalOcean SSH alias `rytivo` works, independently of the Mac connection.
Backend and Nginx were confirmed active. Production APNs key is securely stored
outside the checkout on the droplet with root ownership and backend-group read
access. Never print, commit, or copy the key into an app bundle. HealthKit was
not replaced or removed. Remote push device registration and delivery are NOT
implemented yet; existing local reminders remain separate.

## Resume priorities

1. Complete signed native builds/unit tests and physical-device widget/Live
   Activity integration tests; inspect compact layouts and failure states.
2. Review feature branch and required CI build before merging to main.
3. Finish APNs registration/delivery and end-to-end TestFlight testing.
4. Continue beta readiness audit; this checkpoint is not a beta-readiness signoff.
