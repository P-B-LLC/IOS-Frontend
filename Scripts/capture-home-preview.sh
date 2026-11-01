#!/usr/bin/env bash
# Illustrative, disconnected Debug fixtures in a dedicated simulator.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-$repo/.build/DerivedData/Build/Products/Debug-iphonesimulator/Rytivo.app}"
output="$repo/.build/home-previews"
test -d "$app" || { echo 'Build Debug for iOS Simulator before capturing previews.' >&2; exit 1; }
mkdir -p "$output"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")"
select_runtime() {
    xcrun simctl list runtimes -j | python3 -c '
import json,sys
def version(text): return tuple(int(n) for n in text.split("."))
candidates=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"] and version(r["version"])>=version(sys.argv[1])]
if not candidates: sys.exit(1)
print(max(candidates,key=lambda r:version(r["version"]))["identifier"])
' "$minimum"
}
if ! runtime="$(select_runtime)"; then
    if [ "${DOWNLOAD_HOME_RUNTIME:-0}" != 1 ]; then
        echo "Install an iOS $minimum or newer simulator runtime in Xcode before capturing previews." >&2
        exit 1
    fi
    xcodebuild -downloadPlatform iOS
    runtime="$(select_runtime)"
fi
device_type="$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; types=[t for t in json.load(sys.stdin)["devicetypes"] if "iPhone" in t["name"]]; print(next((t for t in types if t["name"]=="iPhone 17 Pro"),types[-1])["identifier"])')"
device="$(xcrun simctl create 'Rytivo Home visual review' "$device_type" "$runtime")"
primary_device="$device"
narrow_device=''
cleanup() {
    # Only the two simulators this script created; no installed user app is touched.
    for created in "$primary_device" "$narrow_device"; do
        if [ -n "$created" ]; then
            xcrun simctl shutdown "$created" >/dev/null 2>&1 || true
            xcrun simctl delete "$created" >/dev/null 2>&1 || true
        fi
    done
}
trap cleanup EXIT
prepare() {
    xcrun simctl boot "$1"
    xcrun simctl bootstatus "$1" -b
    xcrun simctl install "$1" "$app"
    xcrun simctl status_bar "$1" override --time '9:41' --batteryState charged --batteryLevel 100
}
capture() {
    local name="$1" appearance="$2" fixture="$3" target="${4:-}" large="${5:-0}" language="${6:-en}"
    xcrun simctl ui "$device" appearance "$appearance"
    SIMCTL_CHILD_REPBASE_HOME_PREVIEW="$fixture" \
        SIMCTL_CHILD_REPBASE_APPEARANCE="$appearance" \
        SIMCTL_CHILD_REPBASE_HOME_SCROLL="$target" \
        SIMCTL_CHILD_REPBASE_HOME_LARGE_TEXT="$large" \
        xcrun simctl launch --terminate-running-process "$device" com.pbllc.rytivo -AppleLanguages "($language)"
    sleep 2
    xcrun simctl io "$device" screenshot "$output/$name.png"
}
prepare "$device"
for appearance in light dark; do
    capture "home-$appearance" "$appearance" populated
    capture "food-$appearance" "$appearance" populated home.food
    capture "empty-$appearance" "$appearance" empty
done
capture home-large-text light populated '' 1
capture workout-large-text light populated home.workout 1
capture food-large-text dark populated home.food 1
capture home-arabic dark populated '' 0 ar
capture workout-arabic dark populated home.workout 0 ar
capture food-arabic light populated home.food 0 ar
capture home-japanese light populated '' 0 ja
capture home-german light populated '' 0 de
capture workout-cardio light cardio home.workout
# The narrowest current supported fixture, when installed Xcode offers it.
narrow_type="$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; types=json.load(sys.stdin)["devicetypes"]; print(next((t["identifier"] for t in types if t["name"]=="iPhone SE (3rd generation)"),""))')"
if [ -n "$narrow_type" ]; then
    narrow_device="$(xcrun simctl create 'Rytivo Home narrow review' "$narrow_type" "$runtime")"
    # Keep only one simulator active on the CI runner.
    xcrun simctl shutdown "$primary_device"
    device="$narrow_device"
    prepare "$device"
    capture home-narrow light populated
    capture food-narrow light populated home.food
fi
echo "Illustrative Home previews: $output"
