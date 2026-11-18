# Superset rest and rest-complete banner — testing only

Scope: `work/testflight-fixes-2026-10-27`. This change does not deploy the
backend, change the API contract, merge into `main`, or upload TestFlight.
It implements only the superset-rest and persistent-banner item from the
[approved workout previews](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=421-16172).
Other proposed workout changes remain separate work.

## Expected behavior

- A superset round waits for each applicable exercise's set to be successfully
  logged before automatic rest starts, including when exercises are logged in
  reverse order. Typing into a field alone is not a completed set.
- Bodyweight sets can complete a round without an invented external weight.
  Already-finished exercises with fewer sets must not block later rounds.
- Existing auto-rest off, zero-rest, ordinary-set and drop-set rules remain
  respected. Rest is not needed when the entire workout is complete.
- The compact rest-complete banner can be dismissed immediately and expires
  ten seconds after the countdown's end date. Leaving the screen, backgrounding
  or relaunching does not give an old banner a fresh ten-second window.
- Expiry for an older timer must not clear a new, paused, extended or reset
  timer, or a timer belonging to another session/account.

## Build and open the real app on the Mac

From the existing iOS repository, preserve any local changes first. Do not
discard generated files or use a hard reset to make a pull succeed.

```bash
cd "$HOME/Documents/IOS-Frontend"
git status --short
git fetch origin
git switch work/testflight-fixes-2026-10-27
git pull --ff-only
git log -1 --oneline
open -a Simulator
```

Wait until an iPhone is fully booted. Then:

```bash
INSTALL_SIMULATOR=1 bash Scripts/validate-workout-refresh.sh
```

The script reads the installed Rytivo app's HTTPS API origin if the shell has
not supplied one. If no app is installed, or a different backend is required,
set the intended origin explicitly. For the already-configured Rytivo beta:

```bash
REPBASE_API_URL=https://rytivo.app INSTALL_SIMULATOR=1 \
  bash Scripts/validate-workout-refresh.sh
```

This opens the real app, not a sample-data preview. Use a dedicated test
account. Logging sets sends normal requests to the selected backend; changing
the app branch does not deploy or switch the server to its testing branch.
These timer fixes do not require a new backend endpoint or migration.

The script runs the account-safety tests, builds Debug for the simulator,
installs the app and restarts its process. It preserves the app's local data
and reuses `.build/workout-validation` for Xcode intermediates. It never
automatically deletes other builds or simulator data. A preview flag exported
as `SIMCTL_CHILD_REPBASE_*PREVIEW*` causes an explicit stop rather than silently
launching fixtures. `tests.log` and `build.log` remain in the build directory.

If more than one simulator is booted, close the other simulator devices first
so `booted` selects the intended iPhone. A successful build establishes that
the code compiles, not that all manual checks below have passed.

## Manual verification with a test account

Prepare a named lifting workout with at least two rounds of A and B in the
same superset, plus an ordinary exercise C. Enable automatic rest and choose
a short rest, such as 15 seconds, to make the checks quick.

1. **A then B:** Enter A's values without checking it off: no rest starts.
   Log A successfully: focus may move to B, but rest must not start. Log B:
   rest starts once, and the next round remains available.
2. **B then A:** Start a fresh round/session, log B first, then A. No timer
   after B alone; one timer after A closes the round. Repeat with three
   exercises and a different order.
3. **Incomplete round / rapid taps:** Log one exercise ahead of its partner.
   The outstanding partner must still be required. Rapidly tap a completion
   control or retry a response; confirm no duplicate saved set or timer reset.
   Editing a logged weight must not itself count as logging another set.
4. **Bodyweight / unequal counts:** Pair a bodyweight exercise with a weighted
   exercise. The valid bodyweight set completes normally. Give A two sets and
   B three: once A is complete, B's final applicable round must not wait for
   a nonexistent A set. A completed whole workout should not start a new rest.
5. **Failed save:** Disconnect the network before confirming the closing set.
   A failed/unconfirmed write must not start rest. Reconnect and retry once;
   a successful save should produce the normal progression without duplicates.
6. **Existing preferences:** With automatic rest off, then with rest set to
   zero, log the same pair. No automatic timer. Verify a normal standalone
   exercise still rests and a following drop set still avoids intervening rest.
7. **Auto-dismiss:** Let a timer finish while viewing the session. The compact
   banner appears, then clears ten seconds after that countdown ended. Repeat
   and tap its close button early; it disappears immediately.
8. **Background / relaunch:** Leave the session or background the app before
   expiry; return more than ten seconds after the timer ends. No stale banner
   should appear. Also force-quit/relaunch, let the checkpoint restore, and
   verify an expired banner does not return. Returning five seconds after the
   countdown ends should leave only the remaining five seconds, not ten more.
9. **Race protection:** Before an old banner expires, start another rest or
   reset/extend the existing one. The old expiry must not clear the current
   countdown. Pause a timer for longer than its original deadline, return,
   then resume: it must still show its paused remaining time before resuming.
10. **Session/account boundaries:** Finish or abandon the session, or sign out
    during a pending countdown. A later session/account must never inherit an
    old expiry or banner. Check notification and Live Activity behavior on a
    real iPhone too; simulator results do not prove lock-screen behavior.
11. **Presentation:** Check light/dark, large text, VoiceOver, Reduce Motion,
    and scrolling clear of the bottom navigation. The close action must remain
    reachable and labelled; the visual countdown must not announce every tick.

## Automated checks and promotion gate

`SupersetRoundPolicyTests` exercises progression decisions;
`RestTimerLifecycleTests` covers the end-date-based banner window and stale
expiry identity. Both are registered in `Scripts/test-account-safety.sh` along
with the existing workout/checkpoint tests. Source checks and deterministic
policy tests are not a substitute for the real signed-in checks above.

At the start of this change (November 10, 2026), the existing
[draft PR #42](https://github.com/P-B-LLC/IOS-Frontend/pull/42) conflicted with
`main`; its head was `8d8d4ef6c521595a6ab24967503da5f8e3771961` and had no
check runs. The `CI` workflow supports `workflow_dispatch` for validating the
testing branch without merging unrelated main changes. Verify checks against
the exact newly pushed candidate, not that older head. No passing check grants
permission to merge, deploy or release.

Record the candidate SHA, Mac/Xcode/runtime versions, automated results and
the manual cases actually exercised before promotion. Do not label unexecuted
checks as passed.
