#!/usr/bin/env bash
# Drives the real app against a real, throwaway backend: signs in, deletes a
# started workout (cancel, then confirm), trains a session (set kinds, rest
# timer, units, add/remove/reorder, Finish with the plan question), manages
# saved workouts, explores exercises, follows and unfollows, changes workout
# settings, logs a tennis match with the effort chart, searches and filters
# the exercise library, and switches to Spanish to see activities, the effort
# chart and the library translated live.
#
#   bash Scripts/run-e2e-ui-tests.sh [simulator-udid]
#
# Starts ../repbase (or RYTIVO_BACKEND_DIR) under config.test_e2e on a fresh
# SQLite file in a temporary folder, so it cannot touch a real database, and
# stops it afterwards. Needs the backend's .venv and an iOS simulator.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
backend="${RYTIVO_BACKEND_DIR:-$repo/../repbase}"
python="$backend/.venv/bin/python"
port="${RYTIVO_E2E_PORT:-8765}"
device="${1:-}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/rytivo-e2e.XXXXXX")"
export RYTIVO_E2E_PASSWORD="e2e-$(uuidgen)"
export DJANGO_SETTINGS_MODULE=config.test_e2e
export RYTIVO_E2E_DATABASE="$scratch/db.sqlite3"
export RYTIVO_E2E_MEDIA_ROOT="$scratch/media"
mkdir -p "$RYTIVO_E2E_MEDIA_ROOT"

# A server left on the port from an earlier run would answer the readiness
# check below, and the app would sign in against its database instead.
if lsof -ti "tcp:$port" >/dev/null 2>&1; then
    echo "Port $port is already in use. Stop that server or set RYTIVO_E2E_PORT." >&2
    exit 1
fi

if [ -z "$device" ]; then
    device="$(xcrun simctl create "Rytivo E2E $(date +%s)" com.apple.CoreSimulator.SimDeviceType.iPhone-17)"
    trap 'xcrun simctl delete "$device" >/dev/null 2>&1 || true' EXIT
fi

# A fresh simulator shows the keyboard's one-time "slide to type" tip the
# first time a letter keyboard comes up. Its animation never ends, so every
# step after it waits for an app that never goes idle, and the first test to
# type a word hangs until its ten-minute allowance. Mark the tip as seen.
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl spawn "$device" defaults write com.apple.Preferences DidShowContinuousPathIntroduction -bool true

(cd "$backend" && "$python" manage.py migrate --noinput >/dev/null)
(cd "$backend" && "$python" manage.py shell -c "exec(open('$repo/Scripts/e2e-seed.py').read())")
(cd "$backend" && exec "$python" manage.py runserver "127.0.0.1:$port" --noreload) > "$scratch/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true; xcrun simctl delete "$device" >/dev/null 2>&1 || true' EXIT
until curl -s "http://127.0.0.1:$port/" >/dev/null; do sleep 1; done

derived="$repo/.build/DerivedDataE2E"
xcodebuild build-for-testing -project "$repo/IOS Frontend/IOS Frontend.xcodeproj" -scheme "IOS Frontend" \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived" \
    REPBASE_API_URL="http://127.0.0.1:$port/" CODE_SIGNING_ALLOWED=NO
TEST_RUNNER_RYTIVO_E2E=1 TEST_RUNNER_RYTIVO_E2E_PASSWORD="$RYTIVO_E2E_PASSWORD" \
xcodebuild test-without-building -xctestrun "$(ls "$derived"/Build/Products/*.xctestrun | head -1)" \
    -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 600 \
    -only-testing:RytivoUITests/RytivoE2ETests/test01DiscardStartedWorkout \
    -only-testing:RytivoUITests/RytivoE2ETests/test02LiftingSession \
    -only-testing:RytivoUITests/RytivoE2ETests/test03SavedWorkouts \
    -only-testing:RytivoUITests/RytivoE2ETests/test04ExploreExercises \
    -only-testing:RytivoUITests/RytivoE2ETests/test05Following \
    -only-testing:RytivoUITests/RytivoE2ETests/test06WorkoutSettings \
    -only-testing:RytivoUITests/RytivoE2ETests/test08LogTennis \
    -only-testing:RytivoUITests/RytivoE2ETests/test09ExerciseLibrary \
    -only-testing:RytivoUITests/RytivoE2ETests/test10WorkoutsInAnotherLanguage \
    -only-testing:RytivoUITests/RytivoE2ETests/test11Activity \
    -only-testing:RytivoUITests/RytivoE2ETests/test12CalendarAgenda
