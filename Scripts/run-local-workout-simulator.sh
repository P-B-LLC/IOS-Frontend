#!/usr/bin/env bash
# Real local API + real app, not a sample-data preview or a live account.
# Run the backend's Scripts/run-local-workout-testing.py in another terminal.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${RYTIVO_LOCAL_PORT:-8765}"
[[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || {
    echo 'RYTIVO_LOCAL_PORT must be an integer from 1024 to 65535.' >&2; exit 1;
}
origin="http://127.0.0.1:$port"
output="$repo/.build/local-workout-testing"
derived="$output/DerivedData"
for tool in xcrun xcodebuild python3 curl; do
    command -v "$tool" >/dev/null || { echo "Missing $tool. Run on your Mac with Xcode selected." >&2; exit 1; }
done
developer="$(xcode-select -p)"
simulator_app="$developer/Applications/Simulator.app"
test -d "$simulator_app" || {
    echo 'The selected developer directory has no Simulator app. Select the full Xcode installation with xcode-select first.' >&2
    exit 1
}
verify_backend() {
    local response
    response="$(curl --noproxy '*' --fail --silent --show-error --max-time 5 "$origin/__local_workout_testing__/")" || {
        echo 'Start the separate local workout backend first; no live API fallback is permitted.' >&2; exit 1;
    }
    printf '%s' "$response" | python3 -c '
import json,sys
data=json.load(sys.stdin)
if data.get("environment") != "rytivo-local-workout-testing" or data.get("per_set_targets") is not True:
    sys.exit("This is not the updated isolated local workout backend. Pull its testing branch and restart it.")
'
}
verify_backend
test ! -L "$output" || { echo 'Refusing a linked local simulator state directory.' >&2; exit 1; }
mkdir -p "$output"
chmod 700 "$output"
xcodebuild -project "$repo/IOS Frontend/IOS Frontend.xcodeproj" -scheme 'IOS Frontend' \
    -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
    REPBASE_API_URL="$origin" CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$output/build.log"
app="$derived/Build/Products/Debug-iphonesimulator/Rytivo.app"
actual="$(/usr/libexec/PlistBuddy -c 'Print :REPBASE_API_URL' "$app/Info.plist")"
[ "$actual" = "$origin" ] || { echo 'Built app does not point at the isolated local backend. Not installing.' >&2; exit 1; }
minimum="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")"
runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
def version(text):
    parts=tuple(int(n) for n in text.split(".")); return parts+(0,)*max(0,3-len(parts))
items=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"] and version(r["version"])>=version(sys.argv[1])]
if not items: sys.exit("Install a compatible iOS simulator runtime in Xcode Settings > Components first.")
print(max(items,key=lambda item:version(item["version"]))["identifier"])
' "$minimum")"
state="$output/simulator-uuid"
test ! -L "$state" || { echo 'Refusing a linked simulator UUID file.' >&2; exit 1; }
if [ -f "$state" ]; then
    device="$(< "$state")"
    [[ "$device" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
        echo 'Invalid local simulator UUID. No simulator was changed.' >&2; exit 1;
    }
    xcrun simctl list devices -j | python3 -c '
import json,sys
def version(text):
    parts=tuple(int(n) for n in text.split(".")); return parts+(0,)*max(0,3-len(parts))
items=[(runtime,d) for runtime,rows in json.load(sys.stdin)["devices"].items() for d in rows if d["udid"]==sys.argv[1]]
if len(items)!=1 or items[0][1]["name"]!="Rytivo Local Workout Testing" or not items[0][1].get("isAvailable"):
    sys.exit("Stored local test simulator is unavailable or renamed; no other simulator will be used.")
runtime=items[0][0]
if ".iOS-" not in runtime or version(runtime.split(".iOS-",1)[1].replace("-","."))<version(sys.argv[2]):
    sys.exit("The saved local test simulator has an older runtime than this app supports. Upgrade that dedicated simulator in Xcode first.")
' "$device" "$minimum"
else
    kind="$(xcrun simctl list devicetypes -j | python3 -c '
import json,sys
items=[d for d in json.load(sys.stdin)["devicetypes"] if "iPhone" in d["name"]]
if not items: sys.exit("No iPhone simulator device type is installed.")
print(next((d for d in items if d["name"]=="iPhone 17 Pro"),items[-1])["identifier"])
')"
    device="$(xcrun simctl create 'Rytivo Local Workout Testing' "$kind" "$runtime")"
    [[ "$device" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
        echo 'Simulator creation did not return a UUID.' >&2; exit 1;
    }
    printf '%s\n' "$device" > "$state"
fi
verify_backend
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$app"
# Clear preview flags in this child process only. Never erase an app/account.
while IFS= read -r variable; do
    case "$variable" in SIMCTL_CHILD_REPBASE_*|SIMCTL_CHILD_RYTIVO_E2E*) unset "$variable" ;; esac
done < <(compgen -e)
open -a "$simulator_app" --args -CurrentDeviceUDID "$device"
xcrun simctl launch --terminate-running-process "$device" com.pbllc.rytivo
echo "Real local testing app opened at $origin on its own simulator. No preview flags are set."
echo 'Sign in as local_workout_tester with the separate password you chose in the backend terminal.'
echo 'Your local account and saved workouts persist. Main, TestFlight and the live backend were not changed.'
