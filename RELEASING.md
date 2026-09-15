# Releasing

> Before a first beta, read [BETA_READINESS.md](BETA_READINESS.md). It lists
> what a real user hits on day one — including that a release build needs
> `REPBASE_API_URL` set or it exits on launch, and that photos 404 until media
> is served with `DEBUG` off.

Two things have to be green before a version ships: the backend test suite in
`P-B-LLC/repbase`, and the iOS build checks here. Both already run in CI. Until
the step below is done, **neither one blocks anything** — and that is not a
theoretical worry. Commit `18487ff` failed to compile the app target and
reached `main` regardless, because a red CI run on a push has nothing attached
to it.

## The current release candidate

Recorded 2026-09-15. Both repositories, verified from a clean CI checkout
rather than from either working machine.

| | commit | verified by |
|---|---|---|
| `P-B-LLC/IOS-Frontend` | `87a5991` | CI `build` green: Debug and Release builds, Release plist readback, generated client matches the contract, stable decoded ids, 50 account-safety tests |
| `P-B-LLC/repbase` | `4dfdec4` | CI `test` green on SQLite (339 tests, 3 skipped) and CI `postgres` green on PostgreSQL 17 (**339 tests, 0 skipped**) |

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

A workflow can report a failure; only **branch protection** can refuse a
merge. That lives in repository settings, so no commit can switch it on. What
*is* committed is the ruleset itself, ready to import:

> Settings → Rules → Rulesets → **New ruleset** → **Import a ruleset**, and
> pick `.github/rulesets/protect-main.json` from that repository's checkout.
> Then **Create**.

Once per repository, and the two files differ because the job lists do:
`build` in `IOS-Frontend`, `test` and `postgres` in `repbase`. A job
nobody has ticked is a check nobody is held to, so when a workflow gains a
job, add it to the JSON and import again.

**This changes how you push.** A required check cannot have passed for a
commit that is not on GitHub yet, so pushing straight to `main` starts being
refused: branch, push, open a pull request, let CI run, merge. That is the
whole point — `18487ff` reached `main` exactly because a direct push had
nothing attached to it — but it is a real change to a habit rather than a
silent one, and worth knowing before the first time it stops you.

For a genuine emergency, add yourself to the **Bypass list** after importing.
Left empty, as it ships, the rule applies to everyone including the owner.

Until this is on, the release gate catches a bad **tag** and a bad **commit**
still reaches `main`.

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
