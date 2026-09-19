# Calendar subtask regression checks

The Calendar Anytime section previously rendered its own compact row and
omitted nested subtasks. Parents with subtasks now use `PlannerEntryRow`, the
same checklist used by the planner lists. Ordinary task/event rows are unchanged.

## Device/simulator checks (pending)

- Create an untimed parent with two subtasks. Open Calendar on its date: both
  children must appear under the parent, never as separate top-level tasks.
- Collapse and expand using the count/chevron row. Neither action should open
  the editor or change completion. Tapping the parent title still opens editing.
- Check the first child: count becomes 1 of 2 and parent remains incomplete.
- Check the last child: count becomes 2 of 2 and parent checks automatically.
- Uncheck either child: parent reopens. Reload the day and confirm persistence.
- Rapidly tap while saving: controls must not issue concurrent row mutations.
- Disconnect before checking a child: show the inline error, retain the last
  confirmed state, and allow retry when connected. Do not display false success.
- Add/delete a child using the expanded row; verify the count and parent state
  refresh from the server. Adding to a completed parent should reopen it.
- Check light/dark appearance, VoiceOver checkbox names, and Reduce Motion.
- Confirm ordinary tasks, events, and workout-completion confirmation still work.

## Existing server coverage

`core/tests.py` already covers automatic completion on the final subtask,
reopening a child, adding to a completed parent, deleting the outstanding child,
preventing direct parent completion, ownership, and single-level nesting.
No API or database changes are needed for this UI fix.

## Validation limitation

Local `git diff --check` passes. Native build and the device checks above have
not run for this change: the configured Mac SSH endpoint closed both connection
attempts. This document is a checklist, not a claim of passing runtime tests.
