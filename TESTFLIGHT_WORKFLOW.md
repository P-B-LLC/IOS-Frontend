# TestFlight development workflow

## Superset timing and rest completion — November 10, 2026

This client-only candidate fixes reverse-order superset logging: every member
owing a set in the current round is checked before automatic rest starts.
Only a successful set save advances the round; editing a field or a failed save
does not. Unequal set counts and independent exercises keep their behavior.

The approved compact rest-complete notice expires ten seconds after the stored
timer end date, not ten seconds after opening the screen. A cancellable store
task, foreground reconciliation and a date-based display guard prevent stale
notices from returning. Snapshot/session/account checks stop delayed callbacks
or taps from clearing a newer timer. Existing pause, reset, adjustment, manual
start and early dismissal remain available. No API or backend change is needed.

See [WORKOUT_REST_TESTING.md](WORKOUT_REST_TESTING.md) for real-app Mac build
commands and the manual verification checklist. The scope deliberately excludes
reordering, per-set planning, units and watch connections from the other Figma
previews. Main, live deployments and TestFlight uploads remain untouched.

## Calendar month and followers-only sharing — November 4, 2026

See [CALENDAR_SHARING.md](CALENDAR_SHARING.md) for the new contract, privacy
boundaries, recurring-event migration, design reference, exact staging scope
and validation checklist. Sharing is a separate read-only projection, never
part of own task progress, Home Next up or reminder state. The old design's
Following tab is intentionally omitted: only current followers can be invited.
These changes require the matching backend test branch and fresh generated
client. A testing-branch push is not a main merge, deployment or TestFlight release.

## Food search and results — November 3, 2026

The approved [food-search proposal](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=369-14533)
is implemented on the shared iOS testing branch. A warm adaptive search area
has a labeled Search action and visible barcode/manual-entry choices. Compact,
outlined food cards open nutrition/portion review rather than instantly adding
a food. Recent calories are labeled as the last logged portion; discovery
identities show Details until authoritative nutrition is known. The main
results heading no longer carries the provider name. Source attribution and
ODbL links remain available through the info button and Food data & sources.

The provider/API, explicit-submit policy, stale-response fences, detail lookup,
portion calculations, retry-safe save snapshot and recovery key are unchanged.
No backend deployment, main merge, TestFlight upload or API regeneration is
part of this presentation change. Existing ten-language copy is retained and
new copy is translated in the catalog.

Mac CI builds both configurations, runs the account-safety suite and captures
initial/results/empty/error/loading/large-text states in light and dark, plus
Arabic results. DEBUG-only fixtures cannot make catalogue requests, save diary
entries, or read/write an account's recovered picker draft. These fixtures
are illustrative, not live product data. Source-wiring tests do not replace
rendered review or interaction tests. Before promotion, check a real search,
barcode (device), manual entry, portion edit, save/retry, back/cancel, source
links, VoiceOver, large text, RTL and reduced motion against a test account.

## Home photo clarity — November 3, 2026

The Home workout (including completed), movement and food focus cards opt into
a lighter photographic scrim: the small top label and lower text/actions keep
stronger shading while the image's middle is more visible. Increase Contrast
and accessibility text use stronger protection. Other Training/Profile photo
cards retain their original scrim, and an unknown activity keeps its neutral
fallback. Image interpolation is high quality; no blur, raster upscaling,
network images, data/store changes or extra image copies are introduced.

The existing approved Figma originals replace reduced exports for strength
(577 × 1024 → 941 × 1672) and outdoors (1024 × 683 → 1536 × 1024). Food already
uses its 1152 × 928 image. Assets remain under the existing per-image 3 MiB and
total 16 MiB budgets; the asset check guards against smaller replacements.
Originals came from the existing [category photo sources](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=248-8078),
not newly generated artwork. The prior images remain in integration history.

Mac CI captures the real Home focus cards in light/dark and larger text. Review
all three cards, completed workout, bright portions of each photo, neutral
fallback, narrow width, Increase Contrast, and RTL before promotion. A source
wiring test or a higher pixel count does not establish rendered readability.
Main, TestFlight and the live backend remain outside this testing-only change.

## Food Goals button — November 3, 2026

The approved [Goals proposal](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=352-14502)
replaces the small text-only action with an outlined pill, the exact local
target vector, and a 104 × 44-point minimum tap area. The headline keeps its
width; the date and Goals share a row that stacks when text needs more room.
Existing adaptive surface/accent-text tokens provide light and dark colors;
Increase Contrast strengthens the outline and shared press feedback respects
Reduce Motion. The existing goals full-screen editor, month action, date
selection, stores, goal values, API and backend are unchanged. Existing copy
and its ten-language translations are reused.

Source-wiring tests guard these destinations, dimensions and the local asset.
Mac CI also captures Food in both appearances, larger text, German and Arabic;
the preview script captures a narrow Food page when that runtime is available.
These fixture captures do not prove a signed-in save. Before promotion, tap
Goals from Training and Home's pushed Food page, change/save/cancel targets,
return to Food, and verify its date and totals remain correct. Check VoiceOver,
large text, narrow widths, RTL, Increase Contrast and Reduce Motion. Main,
TestFlight and the backend must remain unchanged until release approval.

## Food page follow-up

The [reviewed Meal planner card](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=339-14270)
replaces the small Plan your week link. It sits after the meal list, directly
above Cookbooks and Add meal, and opens the existing selected-day planner.
Daily nutrients remains the final card. Planning & details is removed;
Nutrition breakdown is available inside Daily nutrients and Goals keeps its
existing entry point. These changes preserve the stores, API and save behavior.
Native CI captures the real planning card in both themes and with larger text.

## Cookbook library: duplicate action and live 404 diagnosis — November 2, 2026

The library now has one **New cookbook** action in its content. The duplicate
navigation-bar plus, its unused presentation state, and its duplicate editor
sheet are removed. Inside an individual cookbook, the existing plus still
creates a recipe and remains disabled when that cookbook is full.

Read-only verification against `https://rytivo.app` found the live backend at
`faac069`, healthy at `/health/` (200), but missing
`/api/v1/food/cookbooks/` (404). Its deployed `core/urls.py` has no cookbook
registration. The existing saved-meal endpoint returns the expected 401 without
credentials. The iOS generated client uses the documented cookbook path with
its trailing slash; this is an undeployed backend feature, not an empty library
or an authentication failure. Pulling/building iOS does not deploy repbase.

Cookbooks remain on repbase's `work/testflight-calendar-sync-2026-10-28` branch.
Before a coordinated rollout, reconcile its cookbook migration chain with
main's `0087_link_workout_calendar_tasks`, validate the merged candidate, and
handle older clients that omit the now-required cookbook destination. Follow
repbase's `COOKBOOKS_TESTING.md` for the database backup and migration procedure.
No live server, database, API contract, or synchronization behavior is changed
by this UI fix. A simulator build alone will continue to receive the live 404.

## Portion screen: simple macro summary — November 3, 2026

The approved [Portion review](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=329-14182)
uses one calorie ring and a carbs/fat/protein legend, the raised Your portion
field, and a pinned Add to meal action. Native segmented pickers and the
decimal text field retain their original bindings. The Portion view is moved
out of FoodPickerView into its own file; its initializer, reference detection,
quantity parsing, six-decimal multiplier, unit conversion and onAdd payload
are preserved. Stores, models, API contracts and backend files are unchanged.
The previous presentation is available in integration history at `7c5f7ff`.

Only the chart's presentation is derived: its shares normalize 4/9/4 macro
energy, with visible percentages reconciled to 100%. The calorie total remains
the food's supplied value. Zero/invalid macro energy produces a neutral ring,
not a complete progress indicator. Invalid quantity, save errors, a locked
retry and the disabled Saving state retain their existing behavior. Large
text moves the heading into the scroll area and shows a vertical text summary.

The native CI build, catalog checks and regression suite include seven macro
presentation checks and the existing portion-conversion/recovery coverage.
Debug-only captures exercise servings, larger servings, grams, millilitres,
zero macros, saving, retry and accessibility text in both appearances. Run
`FOOD_PREVIEW_SCREENS='portion portion-weight portion-accessibility' bash Scripts/capture-cookbooks-preview.sh /path/to/Rytivo.app`
to capture these locally after a Debug simulator build.

Before promotion, use the signed-in simulator to edit fractional quantities,
switch grams/ounces/servings without changing the selected amount, choose
millilitres, expand nutrients, dismiss the keyboard, and add a food. Also
check an invalid amount, a failed/locked retry, a narrow screen, Arabic RTL
and VoiceOver. Preview captures use fixtures and do not verify a live save.

## Meal workspace: gentle depth — November 2, 2026

The approved [Meal review](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=308-14257)
adds a Sunrise heading with a decorative plate, raised Search/Cookbooks/manual
controls, recent-food portion cards, meal totals, and explicit Edit labels.
Done stays above the shell's floating navigation instead of inside the scroll.
The prior UI is preserved in integration history at `e08be05`.

This changes presentation only. Meal IDs, date/slot selection, stores, API
requests, autosave, food deletion, rename/remove, nutrition disclosure, and
all four existing full-screen destinations are retained. Recent cards still
open portion selection; their labels are not additional nested buttons.
Large text reflows controls vertically, Reduce Motion uses the shared press
style, and new copy is translated in all ten languages, including food counts.

On the Mac, use `INSTALL_SIMULATOR=1 bash Scripts/validate-sunrise-refresh.sh`.
The script reads the installed app's HTTPS API configuration when the environment
does not supply one. It installs over the existing app without erasing data.
CI also captures illustrative empty/populated Meal screens in both themes
through the existing debug-only food preview harness. To capture them locally:
`FOOD_PREVIEW_SCREENS='meal meal-empty' bash Scripts/capture-cookbooks-preview.sh /path/to/Rytivo.app`.

Before promotion, check both themes in the signed-in Training tab, a narrow
screen, large text, VoiceOver and Arabic RTL. Open each source of food, choose
a recent portion, edit an entry, expand nutrition, rename/remove a meal and
return with Done/back. Scroll the last entry clear of the footer, and confirm
Done remains above the full and minimized app bar. Preview screenshots use
fixtures and do not verify a live save or the signed-in shell.

## Rotation workout names and saved-plan selection — November 1, 2026

Creating a different workout named `Push Day` when that exact name is already
saved previously submitted a duplicate create and showed only HTTP 400. New
plans now offer an available name such as `Push Day (2)` before saving. The
action changes only the name: the selected exercises, their order and targets,
and the draft's operation identity stay intact. Copying a saved workout also
starts with an available name. The server's per-account name uniqueness stays
in place; no existing workout is overwritten or substituted by its name.

An unconfirmed create keeps its original idempotent retry available, including
after relaunch. A definitive 400 still clears the rejected request snapshot so
the corrected draft can save, while preserving the server's readable reason.
Rotation days separately offer saved workouts by server ID or Create new;
choosing a saved plan writes no template or calendar entry.

Regression coverage includes name suggestions/length limits, pending-save and
account isolation, readable validation errors, repeated rotation templates,
and stale rotation days. On a Mac, run `bash Scripts/test-account-safety.sh`
and build the simulator app. Interactive checks before promotion:

1. Build a new `Push Day` with different exercises from the saved one. Use the
   suggested distinct name and save it into a rotation day. Verify both saved
   plans keep their own exercises, set kinds, targets, rests and order.
2. Choose one saved workout for multiple rotation days. Verify selection does
   not create a duplicate template or schedule any date until the rotation saves.
3. Cancel a new workout and return to the picker; cancel the picker and verify
   the rotation is unchanged. Saving a new workout returns to its rotation day.
4. Interrupt a save after its server write, relaunch and continue the draft.
   Save again to confirm the original operation without creating another plan.

## Branches

Notification-center testing work is documented in
[NOTIFICATION_ACTIVITY_HANDOFF.md](NOTIFICATION_ACTIVITY_HANDOFF.md), including
the two draft PRs, optional backend preview support, Mac generation evidence,
and the simulator/accessibility checklist. It is not a production deployment.

Set up on 2026-10-27 for `P-B-LLC/IOS-Frontend`:

- `main`: release-ready code, changed only through a pull request with passing checks.
- `work/testflight-fixes-2026-10-27`: shared integration/testing branch, based
  on `8e2a58f` (the merged planner redesign, including the food redesign).
- Optional `fix/<short-description>` or `feature/<short-description>` branches
  for parallel work, normally based on the current integration branch.

This setup does not upload a build, change the installed TestFlight app, or
change backend/web repositories. Existing feature and backup branches stay
intact. Keep the integration branch history shared; do not force-push it.

## 1.1 beta candidate — October 30, 2026

Promotion of this integration branch to `main` as version 1.1 (the last
TestFlight build was 1.0 (525), built against `https://rytivo.app`). Its
backend is repbase `work/testflight-calendar-sync-2026-10-28`, promoted in
repbase PR #36, which now also carries the photo/video post backend ported
from repbase PR #34 (migration renumbered `0086_media_posts`).

**Deploy the backend before any tester gets this build.** The server at
`rytivo.app` ran roughly the 2026-10-17 backend, without notifications'
scoped reads, Open Food Facts search and barcodes, activity logging, set
structure, the exercise library or media posts. Build 525 keeps working
against the new backend: the contract change is additive, and an unknown
post kind is kept as a card it cannot draw.

Deploy order on the droplet: confirm the running commit and migrations, back
up the database (`pg_dump -Fc`), stop the timers and the `repbase` service
(migrations 0082/0083 add NOT NULL columns that the old process cannot
insert into), run `deploy/deploy.sh` for the merged `main` SHA, verify
`/health/`, 0086 applied, and 1,023 library rows, then start the timers.
Rolling back after the new code has served means restoring the backup.

Release-review fixes in this candidate: untranslated media-post strings and
a CI check that catches strings missing from the catalog, the composer's
discard leaving a ghost post, Discover state surviving an account switch,
Lock Screen set logging failing while locked (file protection), native
Arabic/Devanagari digits in number fields, last-time hints after relaunch,
duplicate exercises from the session sheet, the rest alert lost on reminder
rescheduling, and silent Finish/plan-update failures. E2E adds activity and
calendar-agenda tests; the runner suppresses the simulator's slide-to-type
tip, which otherwise hangs the first test to type a word.

Device-only checks still owed before inviting external testers: Lock Screen
and Dynamic Island workout controls with the phone locked, rest-over
notification, barcode scanning, camera/photo/video posting, HealthKit.

## Calendar structure refresh — October 30, 2026

The compact task/event buttons sit directly below the brand/header. A compact
weekday selector is restored without its enclosing card. Month, Today and
week arrows sit above the seven day choices. Your day has a separately scrollable hourly
agenda whose height is bounded to part of the screen. All 24 clock hours remain
available, including on empty days. Entries stack within their starting hour
and retain their exact time-range labels; card heights do not claim a duration.
Untimed entries remain outside the hour grid. Completed tasks stay in their
original hourly/anytime rows with checkmarks and strikethrough; there is no
separate Completed section. Overdue tasks and upcoming events stay expandable,
and the overdue count is red in both themes.
Expanding upcoming shows every item already loaded in the existing horizon.
The preceding hourly layout is preserved at `d96e9e3` in integration history.

This is presentation work: planner persistence, completion/subtask requests,
notification scheduling are unchanged. Day navigation uses calendar arithmetic
across DST/year boundaries. The new grouping/initial-position rules have unit
coverage, and new copy has all nine non-English translations. Existing task
rows preserve subtask controls, retry/pending state and workout confirmation.

Before promotion, run `INSTALL_SIMULATOR=1 bash Scripts/validate-planner-refresh.sh`
on the Mac with a booted simulator. When `REPBASE_API_URL` is unset, the script
reads the existing address from the installed Rytivo app's Info.plist; if there
is no installed configuration, set the existing HTTPS origin explicitly.
It reuses `.build/planner-validation` and installs over the existing app,
without erasing simulator data.
Windows syntax/catalog checks do not replace an Xcode build or visual QA.

Interactive checks:

1. Open the month, browse across a month/year boundary, choose a date and return.
   Test Today, weekday selection and both week arrows across month/year and DST boundaries.
2. Add a task/event on a non-today date. Verify scheduled ordering, anytime
   placement, edits, completion/undo, subtask expansion and workout navigation.
3. Filter a day, remove its last matching entry, clear the filter, and switch
   dates. Ensure an empty filter never reads as an empty unfiltered day.
4. Complete and undo both a timed and an anytime task; each must remain in
   its original location, with the same edit/subtask controls and scroll position.
   Expand past-due and upcoming groups. Verify dates and all loaded
   upcoming events are accessible, including more than six. Selected-date items
   must not also appear under the other-day groups.
5. Check loading, retry, editing blocked, empty and all-tasks-complete states.
   Empty days must still show scrollable hours. Scroll to midnight and 23:00;
   test multiple entries in the same hour and expanding subtasks. Refresh/tick
   a task while scrolled: the hour position should not reset. Switching dates
   should position at the first scheduled hour, or the current hour when today is empty.
6. Check light/dark mode, large text, a narrow screen, VoiceOver, Reduce Motion
   and Arabic RTL. Inspect the date/filter controls and verify the inner
   schedule scrolls independently, while other-day disclosures stay reachable.

### Warm week picker — October 30, 2026

The approved [Warm week design](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=138-1630)
is implemented in `PlannerWeekStrip`: opaque peach planned days, a green
surface and check for completed days, and an orange outline for the selected
date. Today remains labelled when another date is selected and after today's
last task is completed. Empty days are not labelled complete; event-only
days stay planned because events are not completable tasks.

The month, Today, and week buttons have visible outlines and 44-point
minimum heights. The controls reflow to two rows on narrow screens or at
larger text sizes. Press feedback respects Reduce Motion, and selecting a
different date provides selection haptics. The existing month sheet, hourly
agenda, inline completion, subtask controls and data requests are retained.
Both new labels have all nine non-English translations. The prior picker is
preserved in branch history at `db9e12e`.

Use the same simulator validation command above. Also check selecting a
completed date, completing/undoing today's last task, browsing away from
Today and returning, an event-only day, French month/Today labels, Arabic
RTL, and a narrow iPhone at larger text sizes. Confirm the selected date's
orange outline remains independent of its green completion state.

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
- Follow-up: search rests as a 72 × 44-point, icon-only glass capsule (no
  “People or #hashtags” prompt). Tapping expands into the existing search
  screen with its text field focused; closing restores the feed. The input
  shares the glass style. Reduce Motion avoids the zoom; Reduce Transparency
  and Increase Contrast use an opaque outlined surface. No API/store changes.
- Own **eligible, server-confirmed published** posts appear in For You.
  Pending uploads remain private status/author content; no moderation bypass.
  The backend puts the newest eligible own publication first on a fresh
  session for 24 hours, with normal session pagination and deduplication.
- iOS reconciles local publication with in-flight reads, deletion and later
  moderation changes. Search requests have cancellation/account fences and
  scoped error/retry feedback. The API contract/generated client is unchanged.
- The concurrent ten-language update (`ffd0261`) was integrated without
  replacing it. New Social labels use the same app-language selection and
  catalog; feed-mode identifiers remain stable while their labels translate.
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

1. Tap the glass search capsule from each Social tab; verify it expands and
   opens the keyboard in one tap. Close it and verify tab/scroll position.
   Open/close rapidly and return from a result: no unwanted keyboard or reset.
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
   RTL, Reduce Motion/Transparency, Increase Contrast, and every tappable
   header control. Source-wiring tests are not visual QA.

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
