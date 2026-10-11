#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
: "${REPBASE_API_URL:?Set REPBASE_API_URL to your configured HTTPS API origin.}"
case "$REPBASE_API_URL" in https://*) ;; *) echo 'Use an HTTPS API origin.' >&2; exit 1;; esac
bash Scripts/generate-api-client.sh
git diff --exit-code -- API/GeneratedSources
bash Scripts/test-account-safety.sh
swift test --filter VideoUploadBodyTests
mkdir -p .build
set -o pipefail
xcodebuild -project 'IOS Frontend/IOS Frontend.xcodeproj' -scheme 'IOS Frontend' \
    -configuration Release -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .build/video-beta CODE_SIGNING_ALLOWED=NO ARCHS=arm64 \
    REPBASE_API_URL="$REPBASE_API_URL" build 2>&1 | tee .build/video-beta-build.log
if [ "${INSTALL_SIMULATOR:-0}" = 1 ]; then
    xcrun simctl install booted '.build/video-beta/Build/Products/Release-iphonesimulator/IOS Frontend.app'
    xcrun simctl launch booted com.pbllc.rytivo
fi
