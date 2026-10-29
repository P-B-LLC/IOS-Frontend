#!/usr/bin/env bash
# Run from the updated work branch on a Mac. Never resets or pulls a checkout.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'This validation requires macOS and Xcode.' >&2
    exit 1
fi
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
xcodebuild -version
bash Scripts/generate-api-client.sh
bash Scripts/test-account-safety.sh
xcodebuild -project 'IOS Frontend/IOS Frontend.xcodeproj' \
    -scheme 'IOS Frontend' -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .build/moderation-validation CODE_SIGNING_ALLOWED=NO build
git diff --check
echo 'Generation, account safety tests and simulator build passed. Review generated source changes before committing.'
