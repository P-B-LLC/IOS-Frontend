# Releasing

Two things have to be green before a version ships: the backend test suite in
`P-B-LLC/repbase`, and the iOS build checks here. Both already run in CI. Until
the step below is done, **neither one blocks anything** — and that is not a
theoretical worry. Commit `18487ff` failed to compile the app target and
reached `main` regardless, because a red CI run on a push has nothing attached
to it.

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

A workflow can report a failure; only **branch protection** can refuse a merge.
That lives in repository settings and cannot be committed, so it has to be
switched on by hand, once per repository:

> Settings → Branches → Add branch ruleset → target `main` →
> **Require status checks to pass**, then select every job the CI workflow
> publishes — at the time of writing `build` in `IOS-Frontend` and `test` in
> `repbase`. Select any new ones as they are added; a job nobody has ticked is
> a check nobody is held to.
>
> Tick **Require branches to be up to date before merging** as well, so a check
> cannot pass against a stale base.

Until that is on, the release gate catches a bad **tag** but a bad **commit**
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
