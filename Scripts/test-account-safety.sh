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
cp "$repo/Tests/AccountSafety/WidgetSnapshotTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/Tests/AccountSafety/WorkoutWidgetControlsTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/IOS Frontend/IOS Frontend/Services/WorkoutWidgetControls.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Models/WidgetSnapshot.swift" "$test_package/Sources/AccountSafety/"
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
cp "$repo/Tests/AccountSafety/ModerationTransportTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/IOS Frontend/IOS Frontend/Models/Weekday.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Views/Navigation/RepbaseRoute.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/IOS Frontend/IOS Frontend/Services/ModerationConsent.swift" "$test_package/Sources/AccountSafety/"
cp "$repo/Tests/AccountSafety/ModerationConsentTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/Tests/AccountSafety/ReportableErrorTests.swift" "$test_package/Tests/AccountSafetyTests/"
cp "$repo/IOS Frontend/IOS Frontend/Models/ReportableError.swift" "$test_package/Sources/AccountSafety/"
for name in AuthenticationStore APIConfiguration KeychainTokenStore; do
    cp "$repo/IOS Frontend/IOS Frontend/API/$name.swift" "$test_package/Sources/AccountSafety/"
done

# Every test file has to appear in the list above, and the list is by hand
# because the sources beside it are: a file that compiles alone goes in, one
# that needs SwiftUI cannot. The failure mode of forgetting is silence -- the
# tests are simply never run, the job stays green, and nothing says which
# ones are missing. So it is asked rather than assumed.
missing=""
for path in "$repo"/Tests/AccountSafety/*Tests.swift; do
    name="$(basename "$path")"
    [ -f "$test_package/Tests/AccountSafetyTests/$name" ] || missing="$missing $name"
done
if [ -n "$missing" ]; then
    echo "These test files are not copied, so they would never run:$missing" >&2
    echo "Add them to $(basename "$0")." >&2
    exit 1
fi

swift test --package-path "$test_package"
