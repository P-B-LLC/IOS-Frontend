#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
export RYTIVO_TEST_REPOSITORY="$repo"
test_package="$(mktemp -d -t rytivo-account-safety)"
mkdir -p "$test_package/Sources/AccountSafety" "$test_package/Tests/AccountSafetyTests"
cp "$repo/Tests/AccountSafety/Package.swift" "$test_package/Package.swift"
cp "$repo/Tests/AccountSafety/AuthenticationSafetyTests.swift" "$test_package/Tests/AccountSafetyTests/"
for name in AuthenticationStore APIConfiguration KeychainTokenStore; do
    cp "$repo/IOS Frontend/IOS Frontend/API/$name.swift" "$test_package/Sources/AccountSafety/"
done
swift test --package-path "$test_package"
