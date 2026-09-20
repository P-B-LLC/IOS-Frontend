#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Required before compiling: the new API operation is generated, not handwritten.
bash Scripts/generate-api-client.sh
bash Scripts/test-account-safety.sh

derived_data=$(mktemp -d /tmp/rytivo-push-build.XXXXXX)
xcodebuild \
  -project "IOS Frontend/IOS Frontend.xcodeproj" \
  -scheme "IOS Frontend" \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  REPBASE_API_URL=https://rytivo.app build

if xcrun simctl getenv booted SIMULATOR_UDID >/dev/null 2>&1; then
  xcrun simctl install booted "$derived_data/Build/Products/Release-iphonesimulator/Rytivo.app"
  xcrun simctl launch booted com.pbllc.rytivo
fi

printf '\nBuild retained at: %s\n' "$derived_data"
printf 'Review and commit the generated API/GeneratedSources diff after successful validation.\n'
printf 'Simulator success does not verify real APNs delivery. TestFlight testing is still required.\n'
