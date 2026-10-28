#!/usr/bin/env bash
# Brings Localizable.xcstrings up to date with the strings the code uses.
#
# Xcode does this after every build in the IDE, but xcodebuild does not, so a
# string added and built only from the command line never reaches the catalog
# and shows in English in every language. This runs the same sync from the
# .stringsdata files a build leaves behind: new strings are added untranslated,
# and strings the code no longer uses are marked stale.
#
#   bash Scripts/sync-localizations.sh [derived-data-path]
#
# Build first (the CI Build step's command will do). Afterwards, translate any
# new entries for every language; the catalog tests fail until they are.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
derived="${1:-$repo/.build/DerivedData}"
catalog="$repo/IOS Frontend/IOS Frontend/Localizable.xcstrings"

# One configuration and architecture: Debug and Release extract the same
# strings, and syncing both would only count each one twice.
objects=$(find "$derived/Build/Intermediates.noindex/IOS Frontend.build" \
    -type d -path "*/Objects-normal/arm64" 2>/dev/null | sort | head -1)
if [ -z "$objects" ]; then
    echo "No build found under $derived. Build the app first." >&2
    exit 1
fi

stringsdata=()
while IFS= read -r -d '' file; do
    stringsdata+=(--stringsdata "$file")
done < <(find "$objects" -name '*.stringsdata' ! -name 'ExtractedAppShortcutsMetadata.stringsdata' -print0 | sort -z)
if [ ${#stringsdata[@]} -eq 0 ]; then
    echo "The build in $objects extracted no strings. Is SWIFT_EMIT_LOC_STRINGS on?" >&2
    exit 1
fi

xcrun xcstringstool sync "$catalog" "${stringsdata[@]}"
echo "Synced $(( ${#stringsdata[@]} / 2 )) source files into $(basename "$catalog")."
