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
