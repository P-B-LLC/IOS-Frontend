#!/usr/bin/env bash
# Copies the exercise library from the backend repository into the app.
#
# One file is the library for both: repbase seeds its shared exercise
# catalogue from core/data/exercise_library.json, and the app ships the same
# file so it can search and filter every exercise offline. Keeping them the
# same file is what lets a library exercise chosen in the app become the
# server's row for it by name. Edit the library in repbase
# (Scripts/exercise_library/), rebuild it there, then run this.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
source="${1:-$repo/../repbase/core/data/exercise_library.json}"
destination="$repo/IOS Frontend/IOS Frontend/Resources/ExerciseLibrary/exercise_library.json"
if [ ! -f "$source" ]; then
    echo "No exercise library at $source" >&2
    exit 1
fi
python3 -I -c 'import json, sys; data = json.load(open(sys.argv[1])); assert data["schema_version"] == 1, "unsupported schema_version"; print(len(data["exercises"]), "exercises, library", data["library_version"])' "$source"
mkdir -p "$(dirname "$destination")"
cp "$source" "$destination"
echo "Copied to $destination"
