#!/usr/bin/env bash
# Debug-only, illustrative fixtures; never signs in or contacts a hosted backend.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-$repo/.build/DerivedData/Build/Products/Debug-iphonesimulator/Rytivo.app}"
output="$repo/.build/cookbook-previews"
test -d "$app" || { echo 'Build Debug for iOS Simulator before capturing previews.' >&2; exit 1; }
mkdir -p "$output"
device="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; devices=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable") and "iPhone" in d["name"]]; print(next((d for d in devices if d["state"]=="Booted"),devices[0])["udid"])')"
xcrun simctl boot "$device" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$app"
for appearance in light dark; do
    xcrun simctl ui "$device" appearance "$appearance"
    for screen in saved cookbook cookbook-picker cookbook-create cookbook-post; do
        SIMCTL_CHILD_REPBASE_FOOD_PREVIEW="$screen" \
            xcrun simctl launch --terminate-running-process "$device" com.pbllc.rytivo
        sleep 2
        xcrun simctl io "$device" screenshot "$output/$screen-$appearance.png"
    done
done
xcrun simctl terminate "$device" com.pbllc.rytivo
echo "Illustrative cookbook previews: $output"
