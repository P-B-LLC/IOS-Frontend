# Exercise order and weight units — testing branch

This client-only change follows the approved [workout flow](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=421-16168).
Scope: `work/testflight-fixes-2026-10-27`. No main merge, backend deployment,
API/schema change or TestFlight upload is included.

## Flow

- Name the workout, then select exercises. Hold the selected exercise card
  itself and drag it into position in Add exercises. There is no separate
  Reorder sheet. The native list handles lift, insertion, cancellation and
  scrolling at its edges; accessible move actions offer a non-drag alternative.
- Moving a card moves its complete exercise record. Local and server IDs,
  set kinds, targets, rest and superset membership stay attached. Reordering
  does not save until the existing Save workout action is confirmed.
- Review checks the selected order and existing targets. Weight unit controls
  appear beside weight entry, with a visible option to save the selected unit
  as the account default. A temporary kg/lb switch does not make a network call.
- Stored weights remain kilograms; display conversion uses the existing exact
  Decimal conversion. Logged results and planned targets remain distinct.

Per-set target tables and watch integrations from the wider proposal are
separate work. This change must not imply those features have shipped.

## Mac: real app, not a fixture

Preserve any local changes before switching or pulling; do not hard-reset.

```bash
cd "$HOME/Documents/IOS-Frontend"
git status --short
git fetch origin
git switch work/testflight-fixes-2026-10-27
git pull --ff-only
git log -1 --oneline
open -a Simulator
```

Once one iPhone simulator is fully booted:

```bash
REPBASE_API_URL=https://rytivo.app INSTALL_SIMULATOR=1 \
  bash Scripts/validate-workout-refresh.sh
```

The explicit origin above is the existing Rytivo beta, not a new testing
server. The script can instead reuse the installed app's HTTPS origin when
`REPBASE_API_URL` is omitted. Choosing the iOS testing branch does not deploy
the server's testing branch. These changes need no new backend endpoint.
Use a dedicated test account: saving a workout or account default still sends
normal authenticated requests to the configured server. The script preserves
app data and reuses build storage; it rejects inherited preview launch flags.

## Manual verification before promotion

1. Add at least 12 exercises. Hold Reverse Fly (or any last card), then move
   it ahead of Triceps. Verify the cards and numbers immediately reflect the
   new order. Ordinary scrolling and the remove button must still work.
2. Hold a card near the top/bottom edge to reach offscreen positions. Move
   first to last and last to first. Cancel an in-progress drag: no missing,
   duplicated, stuck lifted or unexpectedly reordered card.
3. Give exercises different set counts, set kinds, rest times and targets;
   group a pair into a superset. Reorder, review, go Back, save, reopen, and
   start the workout. The order and each exercise's details must agree at
   every step. Repeated catalog movements remain distinct planned entries.
4. Leave without saving: the prior server plan must remain unchanged.
   Verify existing draft recovery behaves normally.
5. In Review and during a lifting session, switch kg to lb and back. Check
   entered weights, logged weights and previous-set hints. Repeated switches
   must not change stored weights. Try 60 kg and 135 lb, decimal commas, empty
   fields and a partially typed decimal before switching.
6. A temporary switch must leave the account default unchanged. Use the
   visible default action, confirm success, then reopen the app. Disconnect
   before saving a default: show a retryable failure, never false success.
   Rapid taps and signing out during a save must not change the next account.
7. Check light/dark, large text, VoiceOver move actions and unit labels,
   Reduce Motion and Arabic/RTL. Controls must remain reachable at small widths.
8. Re-run the previous superset and ten-second rest-banner checks in
   [WORKOUT_REST_TESTING.md](WORKOUT_REST_TESTING.md).

## Evidence limits

Policy/model tests check order, payload and conversion preservation. Source
checks verify wiring but do not prove touch behavior. Isolated DEBUG simulator
fixtures use the real views with local data and cannot save account drafts or
workouts. Their screenshots establish presentation only; they do not establish
drag cancellation, signed-in saves, backend persistence or device behavior.
Record the exact candidate SHA and only checks actually executed. A passing
build never authorizes promotion to main or deployment.
