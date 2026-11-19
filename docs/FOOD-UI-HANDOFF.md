# Food UI refresh — 2026-10-22

Branch: `work/food-tracking-flow-2026-10-22`. Do not merge before Mac build and visual review.

Approved Figma file: `FbMNgG8cuZfrRFzQTtIVCy`. Daily dashboard `48:1120`, open meal detail `63:1187`, portion selection `63:1147`.

## Changes

- Daily fuel summary, Logged/Remaining selection, macro tracks, and meal timeline.
- Empty-meal guidance; open meal summary and food rows; recent food shelf; collapsible nutrition details.
- Food catalogue/recent selection now opens portion review before invoking the existing retry-safe save path.
- Successful save confirmation appears only after the store confirms saving; failed requests retain their entry ID for retry.
- Existing manual entry, saved meals, meal plans, rename/delete, date navigation and sharing routes retained.
- No API contract, generated client, repository, or store changes. Existing brand typography and dynamic colors reused. Rings remain data-driven, not exported sample-value SVGs.

## Validation

Windows syntax parsing and stable-identifier checks are not an Xcode build. Simulator visual matching, accessibility and runtime checks still require the Mac.

From a clean Mac checkout of this branch, with the existing `REPBASE_API_URL` exported and one simulator booted:

```bash
INSTALL_SIMULATOR=1 bash Scripts/validate-food-refresh.sh
```

Check light/dark mode, large Dynamic Type, empty/new account and populated meals. Search food, inspect its real serving definition (catalogue entries may be per 100 g), enter fractional quantities, save, add another, and edit/delete. Verify zero/unset targets and above-target values, different dates, saved meals, plan meals, and offline save/retry without duplication. Ensure closing the picker does not claim a failed save succeeded.

The prototype's example foods, numbers, and history are never shown as real user data. Quantity controls use servings, not guessed grams. Recent foods without a known serving definition retain the existing entry's serving units.
