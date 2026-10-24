# Planner refresh — October 23, 2026

Approved reference: [Figma review board](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=72-1176).
Daily light/dark: `73:1168` / `73:1288`; task: `73:1408`; event: `74:1325`; month: `73:1481`.

## Implementation

- Daily task list is the default. **View month** opens the month overview as a native sheet; selecting a date and **Open this day** returns to its agenda. Closing without a selection restores the selected day's month data.
- Clear Add Task / Add Event actions, a completed-task disclosure, separate event rows, optional category filters and **View timeline** retain existing capabilities.
- Task title opens editing; the leading completion control and trailing Actions menu are separate 44pt targets. Subtask completion remains server-derived, not a local guess. Derived parents have a status mark, not a misleading completion button.
- Editor keeps category, workout link, time, duration, priority, repeat rules/end dates, notes, sharing and deletion. Notification preferences use the existing preferences screen, not a new reminder API. Save remains visible above the keyboard/safe area. Recovery now includes unsaved steps and repeat selections; old checkpoints still decode.
- Existing app typography, navigation and background tokens are reused. Planner-only soft, accessible-accent-text and success colors have light/dark asset variants. No screenshots, remote assets, API changes, or sample data are included in app UI.
- Month reads use latest-request tokens so older successes/errors cannot replace a later month, including A → B → A. Loading indicators distinguish pending data from an empty day. Selected-day entries aren't repeated in Past due / Upcoming.

## Validation status

Windows syntax parsing and diff checks are not an Xcode build. Native compilation, XCTest execution and visual comparison remain pending on macOS.

Local checks passed: eight changed/new Swift files parsed without syntax errors; stable model-ID guard; OpenAPI parse (no contract changes); shell syntax; every XCTest file registered in the runner; `git diff --check`. Planner text-token contrast checks against white/dark raised surfaces: accent text 6.33:1 / 8.63:1, success 6.47:1 / 8.68:1. These checks do not prove rendered geometry or native type checking.

On the Mac, after this branch is available locally, set `REPBASE_API_URL` to the **existing HTTPS API origin** and run:

```bash
open -a Simulator
INSTALL_SIMULATOR=1 bash Scripts/validate-planner-refresh.sh
```

The script runs all AccountSafety tests (including six new calendar/read-order tests), builds Debug, then installs/launches only if those steps succeed. It never deletes the installed app or its data.

## Simulator acceptance checks

1. Compare daily view in light and dark, a small iPhone, and large Dynamic Type. Long task names wrap; the final item scrolls above the app's existing floating navigation.
2. View month → previous/next month rapidly → select a date → Open this day. Repeat across December/January, leap day and DST. Dismiss without selecting; the original day's data returns. Try network failure and Retry, not just a populated happy path.
3. Add task/event for a non-today date; verify saved date, time and duration. Switch Task/Event before saving: event must not receive the task draft's unsaved subtasks. Add a typed-but-unsubmitted step and Save; it must not disappear.
4. Complete/undo a task; expand completed items. Complete the final subtask and reopen it; parent state must match the server. Rapid taps while pending must not duplicate requests. Simulate failure and confirm recovery/error text.
5. Expand/collapse subtasks; add/delete a step, use Actions → Edit/Delete; verify repeat deletion asks the correct scope. Exercise linked workout completion confirmation, filters and timeline.
6. Create custom/weekday repeats with end dates. Navigate to reminder preferences and back without losing the draft. Relaunch mid-draft; steps and repeat choices recover. Verify saving disables mutation and errors keep the draft visible.

Do not declare beta readiness or visual parity until these native checks pass. No commit, push, merge or deployment is implied by this handoff.
