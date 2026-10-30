#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
for tool in swift xcodebuild xcrun; do
    command -v "$tool" >/dev/null || { echo "Run on your Mac with Xcode selected: missing $tool" >&2; exit 1; }
done
if [ "${INSTALL_SIMULATOR:-0}" = 1 ]; then
    xcrun simctl bootstatus booted -b || {
        echo 'Open Simulator and boot an iPhone before running this script.' >&2
        exit 1
    }
    # Keep the installed app's configured backend; never guess a hosted origin.
    if [ -z "${REPBASE_API_URL:-}" ]; then
        installed_app="$(xcrun simctl get_app_container booted com.pbllc.rytivo app 2>/dev/null || true)"
        if [ -n "$installed_app" ]; then
            REPBASE_API_URL="$(/usr/libexec/PlistBuddy -c 'Print :REPBASE_API_URL' "$installed_app/Info.plist" 2>/dev/null || true)"
            export REPBASE_API_URL
        fi
    fi
fi
: "${REPBASE_API_URL:?Set REPBASE_API_URL to your existing HTTPS API origin.}"
case "$REPBASE_API_URL" in https://*) ;; *) echo 'Use an HTTPS API origin.' >&2; exit 1;; esac
bash Scripts/test-account-safety.sh
# Reuse intermediates instead of retaining a new multi-GB build on every run.
build_dir="${DERIVED_DATA_PATH:-$repo/.build/planner-validation}"
mkdir -p "$build_dir"
xcodebuild -project 'IOS Frontend/IOS Frontend.xcodeproj' -scheme 'IOS Frontend' \
    -configuration Debug -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO \
    REPBASE_API_URL="$REPBASE_API_URL" build 2>&1 | tee "$build_dir/build.log"
if [ "${INSTALL_SIMULATOR:-0}" = 1 ]; then
    xcrun simctl install booted "$build_dir/Build/Products/Debug-iphonesimulator/Rytivo.app"
    xcrun simctl terminate booted com.pbllc.rytivo >/dev/null 2>&1 || true
    xcrun simctl launch booted com.pbllc.rytivo
fi
echo "Build retained at: $build_dir"
