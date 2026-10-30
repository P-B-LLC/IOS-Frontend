# Weight and serving entry — October 29, 2026

Testing candidate on `work/testflight-fixes-2026-10-27`, tracked in draft
[iOS PR #39](https://github.com/P-B-LLC/IOS-Frontend/pull/39); not a release.

- FoodPicker's portion review now offers Weight / Servings (Millilitres /
  Servings for a 100 ml catalogue basis), labeled decimal input, and grams/ounces.
- Nutrition and the existing retry-safe save payload continue to use the
  catalogue nutrition multiplier. No API/generated source or backend changes.
- A 100 g catalogue basis defines one displayed catalogue serving as 100 g.
  Other serving descriptions require an explicit grams-per-serving value from
  the label before weight logging. Do not guess a weight or liquid density.
- Changing measurement mode preserves a valid amount when the conversion is
  known. Otherwise the amount is cleared and save stays disabled until valid.
- Controls remain locked during saving/retry. Source serving descriptions are
  shown; user-defined conversion metadata is local to this selection and is
  not persisted as new API fields.

Validation: four new labels translated in all ten languages; catalog JSON
parses and existing translations are unchanged; shell syntax and
`git diff --check` pass. Added production-helper XCTest cases for conversion,
localized digits, invalid values, and save/retry wiring to the existing
account-safety runner. Swift/Xcode execution remains required on macOS/CI;
these tests were not executed on the Windows development machine.

## Developer checkout and environment

Preserve any local work first, then use the testing branch only:

```bash
git fetch origin
git switch work/testflight-fixes-2026-10-27
git pull --ff-only
bash Scripts/test-account-safety.sh
```

For simulator validation use the repository's food validation script with
`REPBASE_API_URL` explicitly set to your approved **test** HTTPS API origin.
Branch isolation does not isolate API traffic: do not point manual write tests
at production accounts. No API origin or server configuration is changed here.
The Open Food Facts backend candidate has not been deployed by this work;
barcode lookup needs that API version in the test environment. Existing scanner
code is already on this branch; the new commit adds measurement selection.

Before release, run `bash Scripts/test-account-safety.sh` and the simulator
build. Check 125 g versus 1.25 catalogue servings (100 g basis), g/oz round trips,
fractional servings, explicit label weights, missing/zero weights, malformed
input, localized decimal separators, liquid units, save failure/retry, dark
mode, VoiceOver and large text. No main merge, deployment or TestFlight upload.
