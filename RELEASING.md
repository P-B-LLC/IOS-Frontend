# Releasing

> Before a first beta, read [BETA_READINESS.md](BETA_READINESS.md). It lists
> what a real user hits on day one — including that a release build needs
> `REPBASE_API_URL` set or it exits on launch, and that photos 404 until media
> is served with `DEBUG` off.

Two things have to be green before a version ships: the backend test suite in
`P-B-LLC/repbase`, and the iOS build checks here. Both run in CI. The iOS `main`
branch is protected by the live **Protect main** ruleset. Since 2026-10-27,
promotion requires a PR and an up-to-date passing build, but no teammate approval.
Use [TESTFLIGHT_WORKFLOW.md](TESTFLIGHT_WORKFLOW.md) for ongoing beta fixes;
backend rules must be verified independently.

## Historical release candidate (2026-09-15)

Recorded 2026-09-15. Both repositories, verified from a clean CI checkout
rather than from either working machine.

| | commit | verified by |
|---|---|---|
| `P-B-LLC/IOS-Frontend` | `309a49c` | CI `build` green: Debug and Release builds, Release plist readback, generated client matches the contract, stable decoded ids, 50 account-safety tests |
| `P-B-LLC/repbase` | `4dfdec4` | CI `test` green on SQLite (339 tests, 3 skipped) and CI `postgres` green on PostgreSQL 17 (**339 tests, 0 skipped**) |

A record cannot name the commit that contains it, so the line above names the
last commit CI has verified. Anything after it here is documentation, which
changes nothing that is built — `87a5991` is the most recent commit that
touches the build at all, and `309a49c` is that plus this file.

The three tests SQLite skips are the row-lock concurrency tests, which skip
themselves unless the database is PostgreSQL. Zero skips on the `postgres` job
is what says they actually ran.

Also checked for this candidate: no migration drift, `openapi.yaml` matches the
serializers, the backend and iOS copies of the contract are byte-identical, and
regenerating the Swift client produces no diff.

**What this candidate still cannot do** is run anywhere but a simulator and a
laptop. It is a dependable build, not a shippable one — see
[BETA_READINESS.md](BETA_READINESS.md) for the five blockers, none of which are
code.

## Cutting a release

1. Make sure `main` is green in both repositories.
2. Tag the version in each: `git tag v1.2.3 && git push origin v1.2.3`.
3. The **Release gate** workflow runs the full CI suite for that tag and fails
   if anything is wrong. It calls `ci.yml` rather than repeating its steps, so
   the checks a release is held to cannot drift away from the checks that run
   on every pull request.
4. Ship only if the gate is green. It writes a plain verdict into the run
   summary either way.

## The part that is a GitHub setting, not a file

A workflow reports a result; the live GitHub ruleset enforces merge gates.
The existing iOS [Protect main ruleset](https://github.com/P-B-LLC/IOS-Frontend/rules/23549107)
requires a pull request, resolved conversations, and
the GitHub Actions `build` check on an up-to-date candidate. Force pushes and
deletion are blocked; the bypass list is empty, including for administrators.
No teammate or latest-push approval is required; the PR author can merge their
own PR once the checks pass and any review conversations are resolved.

`.github/rulesets/protect-main.json` records those settings. It is not applied
automatically by a commit. Update the existing live ruleset deliberately if
the policy changes; do not import an older copy or create a duplicate.

Do not relax protection to finish a release. If a check fails, fix the cause
on a separate branch and rerun validation. GitHub protection cannot prevent a
manual Xcode upload, so release operators must also verify the exact candidate
and its test results before uploading to TestFlight.

## Checking a build without waiting for CI

The simulator build is the one that catches what the SwiftPM account-safety
package cannot: that package is not compiled with the app's
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so actor-isolation mistakes pass
there and fail here.

```bash
xcodebuild -project "IOS Frontend/IOS Frontend.xcodeproj" \
  -scheme "IOS Frontend" \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO build
```
