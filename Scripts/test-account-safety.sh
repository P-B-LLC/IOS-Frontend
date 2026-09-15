#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
export RYTIVO_TEST_REPOSITORY="$repo"
test_package="$(mktemp -d -t rytivo-account-safety)"
mkdir -p "$test_package/Sources/AccountSafety" "$test_package/Tests/AccountSafetyTests"
cp "$repo/Tests/AccountSafety/Package.swift" "$test_package/Package.swift"
cp "$repo/Tests/AccountSafety/AuthenticationSafetyTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/Tests/AccountSafety/WorkoutRecoveryTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/Tests/AccountSafety/EditorDraftRecoveryTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/Tests/AccountSafety/PlannerCompletionTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/Tests/AccountSafety/SocialLikeTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/Tests/AccountSafety/FoodDaySyncTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/IOS Frontend/IOS Frontend/Services/FoodDaySyncCoordinator.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Services/SocialLikeCoordinator.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/Tests/AccountSafety/WorkoutWriteRecoveryTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/IOS Frontend/IOS Frontend/Services/WorkoutWriteRecovery.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Services/PlannerCompletionCoordinator.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Services/EditorDraftRecovery.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Models/RoutePoint.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Services/PendingWorkoutSaves.swift" "$test_package/Sources/AccountSafety/"
# Navigation routing. Both files import nothing but Foundation, which is why
# RepbaseTab and Weekday were lifted out of the view and the workout models --
# a file that needs SwiftUI, or ImperialUnits, cannot be copied in here alone.
cp "$repo/Tests/AccountSafety/NavigationRoutingTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/IOS Frontend/IOS Frontend/Models/Weekday.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Views/Navigation/RepbaseRoute.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Services/ModerationConsent.swift" "$test_package/Sources/AccountSafety/"
for name in AuthenticationStore APIConfiguration KeychainTokenStore; do
    cp "$repo/IOS Frontend/IOS Frontend/API/$name.swift" "$test_package/Sources/AccountSafety/"
done
swift test --package-path "$test_package"
