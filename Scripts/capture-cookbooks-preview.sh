#!/usr/bin/env bash
# Debug-only, illustrative fixtures; never signs in or contacts a hosted backend.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-$repo/.build/DerivedData/Build/Products/Debug-iphonesimulator/Rytivo.app}"
output="$repo/.build/cookbook-previews"
test -d "$app" || { echo 'Build Debug for iOS Simulator before capturing previews.' >&2; exit 1; }
mkdir -p "$output"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")"
select_runtime() {
    xcrun simctl list runtimes -j | python3 -c '
import json,sys
def version(text): return tuple(int(n) for n in text.split("."))
minimum=version(sys.argv[1])
candidates=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"] and version(r["version"])>=minimum]
if not candidates: sys.exit(1)
print(max(candidates,key=lambda r:version(r["version"]))["identifier"])
' "$minimum"
}
if ! runtime="$(select_runtime)"; then
    if [ "${DOWNLOAD_COOKBOOK_RUNTIME:-0}" != 1 ]; then
        echo "Install an iOS $minimum or newer simulator runtime in Xcode before capturing previews." >&2
        exit 1
    fi
    xcodebuild -downloadPlatform iOS
    runtime="$(select_runtime)"
fi
device="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=[d for d in json.load(sys.stdin)["devices"].get(sys.argv[1],[]) if d.get("isAvailable") and "iPhone" in d["name"]]
print(next((d for d in devices if d["state"]=="Booted"),devices[0] if devices else {}).get("udid",""))
' "$runtime")"
if [ -z "$device" ]; then
    device_type="$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; types=[t for t in json.load(sys.stdin)["devicetypes"] if "iPhone" in t["name"]]; print(next((t for t in types if t["name"]=="iPhone 17 Pro"),types[-1])["identifier"])')"
    device="$(xcrun simctl create 'Rytivo cookbook preview' "$device_type" "$runtime")"
fi
xcrun simctl boot "$device" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$app"
original_appearance="$(xcrun simctl ui "$device" appearance)"
trap 'xcrun simctl ui "$device" appearance "$original_appearance" >/dev/null 2>&1 || true' EXIT
for appearance in light dark; do
    xcrun simctl ui "$device" appearance "$appearance"
    for screen in ${FOOD_PREVIEW_SCREENS:-saved cookbook cookbook-picker cookbook-create cookbook-post}; do
        SIMCTL_CHILD_REPBASE_FOOD_PREVIEW="$screen" \
            SIMCTL_CHILD_REPBASE_APPEARANCE="$appearance" \
            xcrun simctl launch --terminate-running-process "$device" com.pbllc.rytivo
        sleep 2
        xcrun simctl io "$device" screenshot "$output/$screen-$appearance.png"
    done
done
xcrun simctl terminate "$device" com.pbllc.rytivo
echo "Illustrative cookbook previews: $output"
