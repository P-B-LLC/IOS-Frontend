# TestFlight development workflow

## Branches

Set up on 2026-10-27 for `P-B-LLC/IOS-Frontend`:

- `main`: release-ready code, changed only through a pull request with passing checks.
- `work/testflight-fixes-2026-10-27`: shared integration/testing branch, based
  on `8e2a58f` (the merged planner redesign, including the food redesign).
- Optional `fix/<short-description>` or `feature/<short-description>` branches
  for parallel work, normally based on the current integration branch.

This setup does not upload a build, change the installed TestFlight app, or
change backend/web repositories. Existing feature and backup branches stay
intact. Keep the integration branch history shared; do not force-push it.

## Social search and own-post confirmation — October 28, 2026

Work remains on `work/testflight-fixes-2026-10-27` in draft
[PR #39](https://github.com/P-B-LLC/IOS-Frontend/pull/39). Backend recommendation
changes are on `work/testflight-calendar-sync-2026-10-28` in draft
[repbase PR #36](https://github.com/P-B-LLC/repbase/pull/36).
Neither branch is a release; do not merge, deploy, or upload TestFlight without
explicit approval.

- Approved design: [Social header](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy/Rytivo-Connected-Flow?node-id=85-1342)
  and [search results](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy/Rytivo-Connected-Flow?node-id=86-1388).
- Persistent search beside Post on For You, Following, and Discover;
  notifications at the upper-right. Closing search preserves the underlying
  feed. People/Posts reuse the existing search endpoints, not a new hashtag
  index, trending service, or exact hashtag token matcher.
- Own **eligible, server-confirmed published** posts appear in For You.
  Pending uploads remain private status/author content; no moderation bypass.
  The backend puts the newest eligible own publication first on a fresh
  session for 24 hours, with normal session pagination and deduplication.
- iOS reconciles local publication with in-flight reads, deletion and later
  moderation changes. Search requests have cancellation/account fences and
  scoped error/retry feedback. The API contract/generated client is unchanged.
- Figma Code Connect setup was requested, but the Code Connect skill requires
  an Organization/Enterprise plan; the connected Byteme plan is Professional.
  No mappings were published. Existing SwiftUI components are reused directly.

Mac validation (from the iOS repository, with the existing HTTPS API origin in
`REPBASE_API_URL` and a simulator already booted):

```bash
git fetch origin
git switch work/testflight-fixes-2026-10-27
git pull --ff-only
INSTALL_SIMULATOR=1 bash Scripts/validate-social-refresh.sh
```

The script runs the account-safety suite and simulator build, then installs
when requested. It reuses `.build/social-validation` to avoid accumulating a
new multi-GB build directory on each run. It does not delete other builds.

Required interactive QA before promotion:

1. Open search from each Social tab; close it and verify tab and scroll position.
2. Search a name, `@handle`, and `#hashtag`; switch People/Posts, clear, retry an
   offline request, and type/clear/retype quickly without stale results.
3. Open a profile, follow/request a private account, open a post/comments,
   like/save/report/block; confirm existing actions and feedback still work.
4. Submit a permitted text/photo/video post. Verify pending status is not a
   public card; after server approval it appears once in For You with a brief
   confirmation. Refresh/reopen and verify backend ordering and deduplication.
5. Delete or moderate a visible post; verify it disappears from all feeds and
   does not return from an older in-flight read. Sign out/switch accounts and
   verify no old post, receipt, or search results remain.
6. Check light/dark mode, a narrow iPhone, larger text, VoiceOver, the keyboard,
   and every tappable header control. Source-wiring tests are not visual QA.

The new backend ordering requires deployment of its tested candidate; a local
simulator build does not deploy server code. Use test accounts/content only
for end-to-end checks. Do not describe local syntax checks as an Xcode build.

## Join the integration branch

First run `git status` and preserve any local changes. Then, from the repository:

```bash
git fetch origin
git switch work/testflight-fixes-2026-10-27
git pull --ff-only
```

On a clone without a local copy, `git switch` creates it from the matching
remote branch. Make changes, commit them, and use `git push` on this branch.
That saves work to the integration branch, not `main`. No teammate approval
is required. Open a PR to `main` only when ready to validate/promote the work
(or use a draft PR to start CI earlier without merging).

For optional independent work, create another branch from there:

```bash
git switch -c fix/short-description
```

Push that branch and open a PR targeting the integration branch. Review and
test the change before combining it with other fixes. Resolve conflicts
without discarding another developer's changes.

## Promote a tested candidate to main

1. Open a PR from the integration branch to `main`; a draft PR can run CI
   while work is still in progress. Branch pushes alone do not run `CI`.
2. Incorporate the latest `main` into the candidate and rerun checks after
   any changes. Never merge based on an earlier commit's green result.
3. Verify the fixed behavior and nearby flows in the simulator. Test affected
   device-only behavior (camera, microphone, HealthKit, notifications, signing)
   on an appropriate device. Record the candidate SHA and test results in the PR.
4. Resolve any review conversations. No teammate, code-owner, or latest-push
   approval is required; the PR author can merge their own passing PR.
5. Merge only after explicit release/promotion approval and all GitHub gates
   pass. Do not bypass a red or pending check.

The required GitHub Actions context is `build`. For code/configuration
changes, it covers Debug/Release simulator builds, Release configuration,
generated-client consistency, stable IDs, account-safety tests, and legal-page
consistency. Markdown-only changes intentionally skip compilation while still
reporting the job and checking legal pages. CI cannot establish that a UI
feels right or that a device-only feature works.

## Live main protection

The existing [Protect main ruleset](https://github.com/P-B-LLC/IOS-Frontend/rules/23549107)
is updated in place, not replaced by a second overlapping ruleset:

- Pull requests required; zero approving reviews required.
- No code-owner, latest-push, or extra unattributed-change approval requirement.
- Stale-review dismissal is disabled; no peer sign-off is needed after updates.
- All review conversations must be resolved.
- `build` must pass from GitHub Actions (integration ID `15368`), against the
  latest target branch.
- Branch deletion and force pushes blocked.
- No bypass actors, including owners/admins. Administrators still have the
  separate power to change repository settings; do not use that to evade checks.
- Both `main` explicitly and the default branch are covered.

There is no `CODEOWNERS` file, so no ownership requirements are invented.
`.github/rulesets/protect-main.json` mirrors the policy. Editing that file
alone does not update GitHub. Verify live settings before any later policy
change and preserve stronger protections.

## Releases

Follow `RELEASING.md` for tagging and release validation. A green PR or release
gate does not automatically upload to TestFlight. Manual Xcode uploads remain
possible outside GitHub: only upload an explicitly approved, tested candidate.

## Calendar/workout sync candidate — 2026-10-28

Work stays on this testing branch; no main merge or deployment is authorized.
The user authorized pushing testing branches and opening draft PRs for CI.

- Workouts now publish a calendar revision after refreshes and schedule changes,
  including an empty schedule or a change outside the current week.
- Confirmed workout finishes, recovered finishes, and session deletions also
  refresh planner completion. A local recovery-file cleanup failure or a later
  failure in a multi-session undo must not hide earlier confirmed changes.
- Planner refreshes authoritative month, overdue, upcoming, and reminder data
  instead of treating the sync endpoint's newly created rows as a full snapshot.
- Refreshes coalesce without losing the final change. Read tokens prevent old
  month/week/reminder responses from restoring deleted entries after a change.
- Home uses concrete dates, not weekday names alone, and its current week stays
  loaded even while Calendar browses another month.
- The backend counterpart is `P-B-LLC/repbase` branch
  `work/testflight-calendar-sync-2026-10-28`. Client refresh alone cannot repair
  planner tasks that the old backend left in the database after schedule deletion.
  Backend rollout must include the new schedule provenance migration. Do not
  guess-delete old unlinked planner entries: they cannot reliably be distinguished
  from manually written workout tasks.

Before promotion, run the draft PR's Mac build and account-safety tests, then
check against a backend running the counterpart branch with a test account:

1. Enable a rotation; verify Workouts, Home, Calendar, and next-up tasks agree.
2. Stop it, then clear the schedule. Unfinished generated tasks should disappear
   everywhere; completed workout history and personal tasks/events must remain.
3. Add a saved workout manually and verify it appears on the same date in all
   three views. Change only a future week and verify Calendar catches up too.
4. Make successive schedule changes on a slow connection. The final state must
   win without duplicate tasks or a stuck loading indicator.
5. Browse another month, then return Home. Today's agenda must remain available.
   On a Sunday-first Home calendar, a previous Sunday must not show next Sunday's
   workout or navigate into that different date.
6. Delete a generated planner task deliberately; a refresh must not recreate it.
   Check reminders are removed for deleted plans, and sign-out cannot carry one
   account's pending refresh into another account.
7. Finish a scheduled workout. Its Home/Calendar task should become completed
   without relaunching or changing months, and its reminder should be removed.
8. Undo that workout's completion in Training. Home/Calendar must reflect the
   server's resulting task state. Also test multiple sessions on one day and a
   failure after one deletion: earlier confirmed changes must still refresh.
9. Attempt Finish offline, restore connectivity, then retry Finish or its saved
   recovery. Only server-confirmed completion should update Home/Calendar; a
   recovery retry must refresh them just like a live Finish.

Local Windows checks cover Swift syntax parsing, stable IDs, shell syntax, and
diff hygiene only. They do not substitute for XCTest/Xcode or real-device QA.

## Workout builder and saved-plan identity — 2026-10-28

The next testing-branch candidate repairs creation and start selection without
changing the API contract. Creating a workout previously looked up an existing
template by normalized name and silently scheduled it, skipping the new draft's
selected exercises. A stale Start selection could also fall back to the first
workout of the day. Both substitutions are removed: create sends the selected
exercise IDs/order/targets, save success requires confirmed read-back, and Start
requires the exact selected workout and matching session exercises. Save retry
keeps its original idempotency key until read-back succeeds.

The day screen removes the no-op View button and swipe-only workout pager. Each
saved workout has one named card, its exercises, and its own Start action.
Completed history appears inside that card instead of being repeated above a
generic Strength session row. Completion, redo, and undo for saved plans use
template IDs, not matching names. Home/Training/linked planner badges use the
same identity. Unlinked manual planner tasks keep their read-only name fallback.

The builder starts blank, shows selected exercises above the catalog, and labels
drafts versus confirmed saves. Continuing an unfinished local draft is explicit.
Saved workouts are copied only when deliberately chosen; exact duplicate new
names are explained, not silently reused. Existing account templates/history are
not deleted or inferred to be premade data.

Simulator/device QA before promotion:

1. Create a uniquely named leg workout with exercises different from an older
   saved leg plan. Add, remove, reorder, and change target sets. Confirm every
   selection appears immediately in the selected tray and review.
2. Save it and verify its named card appears on the chosen day with the same
   exercises/order/sets. Start from that card and verify the session matches.
3. Schedule two workouts on one day. Start the second; never substitute the
   first. Edit one plan and confirm the next session uses its updated contents.
4. Attempt an exact existing name: explain the conflict and retain the draft.
   Explicitly copying a saved plan must require a distinct new name.
5. Interrupt Save after the write but before read-back. Retry without duplicate
   creation or an empty success screen. Sign out/in without cross-account drafts.
6. Close an unfinished editor and reopen it. Continue restores the draft;
   Discard returns to the fresh/current plan without deleting saved workouts.
7. Finish and undo a workout. Other templates (including similarly named ones)
   must keep their own completion/history. The saved plan stays distinct from
   the recorded session, including its optional cardio finisher.
8. Check Light/Dark mode, large accessibility text, long workout/exercise names,
   VoiceOver labels, and scrolling clear of the bottom navigation bar.

`WorkoutSelectionTests` covers create transport, exact identity and ordering,
retry payloads, and save/start wiring. `WorkoutPresentationTests` guards UI
wiring only; it does not render SwiftUI or replace the interaction checks above.
