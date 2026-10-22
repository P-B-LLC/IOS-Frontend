# Approved workout UI implementation

Implementation branch: `work/ui-refresh-2026-10-19`. Main promotion requested
by the owner on October 21, 2026. Native build/test verification remains
pending; promotion is not a claim that those checks passed.

Pre-refresh code is preserved on `backup/pre-workout-refresh-2026-10-21`
at `48db8b7`. Approved Figma references are preserved in Design/WorkoutRefresh.

- Workout-first dashboard, light date tiles, compact daily walking trail.
- Scheduled days use a warm orange tint; completed days use green. A day
  with several scheduled workouts becomes green only after all are finished,
  with no active session remaining. Today retains its orange outline.
- Recoverable guided identity, real exercise picker, target-set review and save.
- API exercise pages load on demand. Search and muscle filters cover loaded
  pages only, explicitly labeled; the OAS has no substring-search endpoint.
  No sample exercise catalog or fabricated metadata is shipped.
- Target sets, ordering, removal with undo, custom exercise creation, previous
  workout reuse, and optional cardio finishers.
- Focused lifting entry, elapsed time, confirmed-set progress, editing, extra
  sets and exercise switching without changing completion or exercise order.
- Account weight preference controls display; API values remain Decimal kg.
- Partial-finish confirmation and actual-count completion summary. Existing
  sharing, PRs, progress charts and cardio finishing remain available.
- Existing confetti reused after confirmed workout completion or observed
  daily step-goal crossing. No confetti with Reduce Motion; no celebration on
  page opening or goal edits. No backend endpoint/schema or generated-client
  changes required.

## Validation status

Local stable-ID validation, API YAML parsing, shell syntax, whitespace checks,
and syntax parsing of the changed Swift files completed. The independent
Swift parser has a known error on an unchanged pre-existing `for ... in try`
loop in WorkoutAPIRepository; no errors in newly added code.

Regression XCTest coverage added for focus selection, wraparound, completed
exercise selection, step-goal threshold crossings, goal edits, missing data,
day rollover, and weight conversion. Tests are included in the existing
account-safety runner, but could not execute: Windows has no Swift toolchain.

Xcode compilation and rendered simulator verification remain required. The
Mac SSH host closed the connection during the build attempt. Do not interpret
syntax parsing or this document as a passing native build or beta approval.

On the Mac, after these files have been transferred/pulled and with the
existing HTTPS API origin exported as `REPBASE_API_URL`:

```bash
INSTALL_SIMULATOR=1 bash Scripts/validate-workout-refresh.sh
```

Manual checks: create/reuse/custom exercises; cancel/back/restore draft; search
across loaded pages; target sets minimum; reorder/remove/undo; save failure;
kg/lb entry; rapid log taps; offline retry; switch with unlogged input; switch
back; partial finish; saved summary; no repeat confetti; light/dark, keyboard,
VoiceOver and large Dynamic Type. Physical Health updates are required to
validate the step-goal crossing on device.
