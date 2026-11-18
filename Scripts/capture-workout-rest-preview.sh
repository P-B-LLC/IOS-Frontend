#!/usr/bin/env bash
# Render the real Debug rest-banner view with a disconnected workout fixture.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-$repo/.build/DerivedData/Build/Products/Debug-iphonesimulator/Rytivo.app}"
output="$repo/.build/workout-rest-previews"
for tool in xcrun python3; do
    command -v "$tool" >/dev/null || { echo "Missing $tool; run this on the Mac with Xcode selected." >&2; exit 1; }
done
test -d "$app" || { echo 'Build Debug for iOS Simulator before capturing previews.' >&2; exit 1; }
mkdir -p "$output"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")"
select_runtime() {
    xcrun simctl list runtimes -j | python3 -c '
import json,sys
def version(text):
    parts=tuple(int(n) for n in text.split("."))
    return parts + (0,) * max(0, 3-len(parts))
candidates=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"] and version(r["version"])>=version(sys.argv[1])]
if not candidates: sys.exit(1)
print(max(candidates,key=lambda r:version(r["version"]))["identifier"])
' "$minimum"
}
if ! runtime="$(select_runtime)"; then
    if [ "${DOWNLOAD_WORKOUT_RUNTIME:-0}" != 1 ]; then
        echo "Install an iOS $minimum or newer simulator runtime in Xcode before capturing previews." >&2
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
device="$(xcrun simctl create 'Rytivo Rest banner visual review' "$device_type" "$runtime")"
# Cleanup can target only the new UUID returned by create, never "booted" or
# another simulator's name. No user's simulator/app or backend is touched.
if [[ ! "$device" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    echo 'Simulator creation did not return a UUID; refusing cleanup by an ambiguous identifier.' >&2
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

# Earlier screen fixtures can win the root-view routing before the workout
# fixture. Clear them only in this script's child environment.
while IFS= read -r variable; do
    case "$variable" in SIMCTL_CHILD_REPBASE_*PREVIEW*) unset "$variable" ;; esac
done < <(compgen -e)

capture_pair() {
    local appearance="$1" suffix="${2:-}"
    xcrun simctl ui "$device" appearance "$appearance"
    SIMCTL_CHILD_REPBASE_WORKOUT_PREVIEW=rest-complete \
        SIMCTL_CHILD_REPBASE_APPEARANCE="$appearance" \
        xcrun simctl launch --terminate-running-process "$device" com.pbllc.rytivo -AppleLanguages '(en)'
    # The fixture sets endsAt when this process starts. The first image should
    # show the finished banner; the second is the SAME launch after expiry.
    sleep 3
    xcrun simctl io "$device" screenshot "$output/rest-complete-$appearance$suffix.png"
    sleep 9
    xcrun simctl io "$device" screenshot "$output/rest-cleared-$appearance$suffix.png"
}
capture_pair light
capture_pair dark
if xcrun simctl ui "$device" content_size accessibility-extra-large; then
    capture_pair dark '-large-text'
else
    echo 'This simulator does not support the requested accessibility content size; large-text capture skipped.' >&2
fi
for appearance in light dark; do
    for state in complete cleared; do
        test -s "$output/rest-$state-$appearance.png" || { echo "Missing rest-$state-$appearance preview." >&2; exit 1; }
    done
done
echo "Illustrative rest-banner previews: $output"
echo 'Inspect both states; screenshots alone do not prove a signed-in save or superset progression.'
