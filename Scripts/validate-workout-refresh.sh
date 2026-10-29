#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
for tool in swift xcodebuild xcrun; do
    command -v "$tool" >/dev/null || { echo "Run this on the Mac with Xcode selected: missing $tool" >&2; exit 1; }
done
: "${REPBASE_API_URL:?Set REPBASE_API_URL to the configured HTTPS API origin.}"
case "$REPBASE_API_URL" in https://*) ;; *) echo 'Use an HTTPS API origin.' >&2; exit 1;; esac
bash Scripts/test-account-safety.sh
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/rytivo-workout-refresh.XXXXXX")"
xcodebuild -project 'IOS Frontend/IOS Frontend.xcodeproj' -scheme 'IOS Frontend' \
    -configuration Debug -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO \
    REPBASE_API_URL="$REPBASE_API_URL" build 2>&1 | tee "$build_dir/build.log"
if [ "${INSTALL_SIMULATOR:-0}" = 1 ]; then
    xcrun simctl install booted "$build_dir/Build/Products/Debug-iphonesimulator/Rytivo.app"
    xcrun simctl launch booted com.pbllc.rytivo
fi
echo "Build retained at: $build_dir"
