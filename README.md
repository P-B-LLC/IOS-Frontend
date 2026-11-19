# Rytivo iOS

The iOS client for Rytivo: SwiftUI, iPhone and iPad, iOS 26.5 or later,
built with Xcode 26 or newer. Version 1.1 is in TestFlight.

The generated networking module keeps its `RepbaseAPI` name because it is
part of the existing backend contract, not user-facing product branding.

Backend-integrated features are contract-first. Read [API/API.md](API/API.md),
[API/openapi.yaml](API/openapi.yaml), and [API/INTEGRATION.md](API/INTEGRATION.md)
before changing API-facing models or behavior.

## Layout

```
IOS Frontend/
  IOS Frontend.xcodeproj   Uses folder-synchronised groups: files added or moved
                           on disk are picked up without editing the project
  Info.plist               REPBASE_API_URL, the server a build talks to
  IOS Frontend/            The app
    API/                   Repositories over the generated client, one per area
    Models/                Value types the app reads and writes
    Services/              Logic with no view: policies, coordinators, localisation
    Stores/                Observable state the screens share
    Views/                 Screens by area: Authentication, Food, Home, Navigation,
                           Planner, Profile, Shared, Social, Workouts (Session/
                           for the live session), Debug (DEBUG-only probes)
    LiveActivity/          Lock Screen and Dynamic Island workout activity
    Resources/             Fonts and the bundled exercise library
    Localizable.xcstrings  Every user-facing string, in ten languages
  RytivoWorkoutActivity/   The widget extension for the Live Activity
  RytivoUITests/           UI and end-to-end tests
API/                       openapi.yaml (copied from ../repbase) and the
                           generated client in GeneratedSources/ -- never edit by hand
Tests/AccountSafety/       Unit tests, run as a Swift package by Scripts/test-account-safety.sh
Scripts/                   Build, check, capture and release scripts
Design/, Brand/, Legal/    Design references, brand marks, legal source text
docs/                      Release workflow, testing guides, feature handoffs
```

## Build and run

Open `IOS Frontend/IOS Frontend.xcodeproj` and run the `IOS Frontend` scheme,
or from a terminal:

```sh
xcodebuild -project "IOS Frontend/IOS Frontend.xcodeproj" -scheme "IOS Frontend" \
  -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
```

Debug builds talk to the server in `REPBASE_API_URL`. To run against a real
local backend with throwaway data, start `../repbase/Scripts/run-local-workout-testing.py`
in one terminal and `bash Scripts/run-local-workout-simulator.sh` in another
(see [docs/WORKOUT_LOCAL_TESTING.md](docs/WORKOUT_LOCAL_TESTING.md)).

## Test

```sh
bash Scripts/test-account-safety.sh      # unit tests (~650), about a minute
bash Scripts/run-e2e-ui-tests.sh         # end-to-end UI tests against ../repbase, 25+ minutes
RYTIVO_E2E_ONLY="test02LiftingSession test11Activity" bash Scripts/run-e2e-ui-tests.sh
```

`test-account-safety.sh` copies the sources that compile without SwiftUI into
a temporary package and runs every file in `Tests/AccountSafety/`. A new test
file must be added to the script; it refuses to run if one is missing. The
end-to-end runner starts the backend from the sibling repository on a
throwaway database and a fresh simulator.

CI (`.github/workflows/ci.yml`) also runs these checks, all runnable locally:

```sh
bash Scripts/generate-api-client.sh                        # client matches API/openapi.yaml
python3 Scripts/check-stable-ids.py
python3 Scripts/check-sunrise-assets.py
python3 Scripts/check-brand-assets.py
python3 Scripts/check-localization-coverage.py .build/DerivedData   # after a build
```

## Release

TestFlight builds are archived with `Scripts/archive-for-testflight.sh`. Follow
[docs/TESTFLIGHT_WORKFLOW.md](docs/TESTFLIGHT_WORKFLOW.md) and
[docs/RELEASING.md](docs/RELEASING.md). Contributors and agents should also read
[AGENTS.md](AGENTS.md) and [docs/LOCALIZATION.md](docs/LOCALIZATION.md).
