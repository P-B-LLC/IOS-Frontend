#!/usr/bin/env bash
# Isolated native workout-builder/unit previews and optional touch tests.
# No login, account draft, live API, backend process, or user simulator is used.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived="${WORKOUT_FLOW_DERIVED_DATA:-$repo/.build/DerivedData}"
app="${1:-$derived/Build/Products/Debug-iphonesimulator/Rytivo.app}"
output="$repo/.build/workout-flow-previews"
for tool in xcrun python3; do
    command -v "$tool" >/dev/null || { echo "Missing $tool; run on a Mac with Xcode selected." >&2; exit 1; }
done
test -d "$app" || { echo 'Build Debug for iOS Simulator first.' >&2; exit 1; }
mkdir -p "$output"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")"
select_runtime() {
    xcrun simctl list runtimes -j | python3 -c '
import json,sys
def version(text):
    parts=tuple(int(n) for n in text.split("."))
    return parts+(0,)*max(0,3-len(parts))
candidates=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"] and version(r["version"])>=version(sys.argv[1])]
if not candidates: sys.exit(1)
print(max(candidates,key=lambda r:version(r["version"]))["identifier"])
' "$minimum"
}
if ! runtime="$(select_runtime)"; then
    if [ "${DOWNLOAD_WORKOUT_RUNTIME:-0}" != 1 ]; then
        echo "Install an iOS $minimum or newer simulator runtime in Xcode." >&2
        exit 1
    fi
    xcodebuild -downloadPlatform iOS
    runtime="$(select_runtime)"
fi
device_type="$(xcrun simctl list devicetypes -j | python3 -c '
import json,sys
types=[t for t in json.load(sys.stdin)["devicetypes"] if "iPhone" in t["name"]]
if not types: sys.exit(1)
print(next((t for t in types if t["name"]=="iPhone 17 Pro"),types[-1])["identifier"])
')"
device="$(xcrun simctl create 'Rytivo Workout flow visual review' "$device_type" "$runtime")"
if [[ ! "$device" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    echo 'Simulator creation did not return a UUID; refusing ambiguous cleanup.' >&2
    exit 1
fi
cleanup() {
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
    xcrun simctl delete "$device" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$app"
xcrun simctl status_bar "$device" override --time '9:41' --batteryState charged --batteryLevel 100
# Clear only this child process's inherited fixture flags, never app/user data.
while IFS= read -r variable; do
    case "$variable" in SIMCTL_CHILD_REPBASE_*PREVIEW*) unset "$variable" ;; esac
done < <(compgen -e)

capture() {
    local screen="$1" appearance="$2" suffix="${3:-}" language="${4:-en}"
    xcrun simctl ui "$device" appearance "$appearance"
    SIMCTL_CHILD_REPBASE_WORKOUT_PREVIEW="$screen" SIMCTL_CHILD_REPBASE_APPEARANCE="$appearance" \
        xcrun simctl launch --terminate-running-process "$device" com.pbllc.rytivo -AppleLanguages "($language)"
    sleep 3
    xcrun simctl io "$device" screenshot "$output/$screen-$appearance$suffix.png"
}
for appearance in light dark; do
    for screen in builder-order builder-reordered builder-units session-units; do
        capture "$screen" "$appearance"
    done
done
if xcrun simctl ui "$device" content_size accessibility-extra-large; then
    for screen in builder-order builder-units session-units; do
        capture "$screen" dark '-large-text'
    done
    xcrun simctl ui "$device" content_size large
fi
for screen in builder-order builder-units; do capture "$screen" dark '-arabic' ar; done
for appearance in light dark; do
    for screen in builder-order builder-reordered builder-units session-units; do
        test -s "$output/$screen-$appearance.png" || { echo "Missing $screen-$appearance preview." >&2; exit 1; }
    done
done

if [ "${RUN_WORKOUT_FLOW_UI_TESTS:-0}" = 1 ]; then
    # The existing UI-test target is reused, but only the isolated fixture
    # class runs. The signed-in E2E class is neither enabled nor selected.
    # End the simctl-owned launch before XCTest installs/launches its target.
    # Otherwise the first test can attach to that process's old launch state.
    xcrun simctl terminate "$device" com.pbllc.rytivo >/dev/null 2>&1 || true
    xcrun simctl spawn "$device" defaults write com.apple.Preferences DidShowContinuousPathIntroduction -bool true
    for key in KeyboardContinuousPathEnabled KeyboardPrediction KeyboardAutocorrection \
        KeyboardInlinePredictions KeyboardShowPredictionBar; do
        xcrun simctl spawn "$device" defaults write com.apple.Preferences "$key" -bool false
    done
    xcrun simctl ui "$device" appearance light
    xcrun simctl ui "$device" content_size large
    xcodebuild build-for-testing -project "$repo/IOS Frontend/IOS Frontend.xcodeproj" -scheme 'IOS Frontend' \
        -configuration Debug -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived" \
        REPBASE_API_URL=https://ci.invalid CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$output/ui-build.log"
    xctestrun=""
    for candidate in "$derived"/Build/Products/*.xctestrun; do
        [ -f "$candidate" ] || continue
        if [ -z "$xctestrun" ] || [ "$candidate" -nt "$xctestrun" ]; then xctestrun="$candidate"; fi
    done
    test -n "$xctestrun" || { echo 'No built UI test plan found.' >&2; exit 1; }
    # Record only build paths, never launch environments or account details.
    python3 -c '
import json, plistlib, sys
with open(sys.argv[1], "rb") as source:
    plan = plistlib.load(source)
def targets(value):
    if isinstance(value, dict):
        paths = {key: value[key] for key in ("TestHostPath", "TestBundlePath", "UITargetAppPath") if key in value}
        if paths: print(json.dumps(paths, sort_keys=True))
        for child in value.values(): targets(child)
    elif isinstance(value, list):
        for child in value: targets(child)
targets(plan)
' "$xctestrun" | tee "$output/ui-test-target-paths.log"
    result="$output/WorkoutFlow-$(date +%s).xcresult"
    if TEST_RUNNER_RYTIVO_WORKOUT_FLOW=1 \
        xcodebuild test-without-building -xctestrun "$xctestrun" \
        -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO \
        -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
        -resultBundlePath "$result" \
        -only-testing:RytivoUITests/WorkoutFlowUITests 2>&1 | tee "$output/ui-tests.log"; then
        ui_status=0
    else
        ui_status=$?
    fi
    # xcodebuild can succeed when an opt-in class was entirely skipped. Grade
    # the four distinct native cases as well as the process exit status.
    if ! python3 -c '
import re,sys
expected={
    "testWholeCardLongPressMovesExerciseAndKeepsReviewTargets",
    "testWholeCardDragCanAutoscrollPastInitiallyVisibleExercises",
    "testBuilderUsesAccountUnitWithoutAnExerciseUnitSwitch",
    "testActiveExercisesKeepIndependentUnitsAndTypedWeights",
}
passed=set()
bad=[]
for line in sys.stdin:
    if not re.search(r"\btest case\b.*\bWorkoutFlowUITests\b",line,re.I):
        continue
    if re.search(r"\b(?:failed|skipped)\b",line,re.I):
        bad.append(line.strip())
    if re.search(r"\bpassed\b",line,re.I):
        name=re.search(r"\bWorkoutFlowUITests(?:\.|\s+)(test\w+)\b",line)
        if name: passed.add(name.group(1))
if passed != expected or bad:
    print("Native workout checks incomplete: expected 4 distinct passing cases, zero skipped/failed.",file=sys.stderr)
    print("Missing: "+", ".join(sorted(expected-passed)),file=sys.stderr)
    print("Unexpected: "+", ".join(sorted(passed-expected)),file=sys.stderr)
    for line in bad: print(line,file=sys.stderr)
    sys.exit(1)
print("All 4 native workout-flow cases executed and passed; none skipped or failed.")
' < "$output/ui-tests.log"; then
        ui_status=1
    fi
    # The real review card may need scrolling. Native tests attach images at
    # that point, so preserve those images as well as the initial screenshots.
    if [ -d "$result" ] && xcrun xcresulttool export attachments --help >/dev/null 2>&1; then
        xcrun xcresulttool export attachments --path "$result" \
            --output-path "$output/interaction-attachments-$(date +%s)" || \
            echo 'Attachment export failed; the full xcresult remains in the artifact.' >&2
    fi
    [ "$ui_status" = 0 ] || exit "$ui_status"
fi
echo "Native workout-flow previews: $output"
echo 'Static reordered previews illustrate state; the opt-in native tests exercise actual gestures.'
echo 'These disconnected tests do not prove a signed-in server save or account preference persistence.'
