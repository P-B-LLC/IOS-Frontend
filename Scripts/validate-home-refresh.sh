#!/usr/bin/env bash
# Share the established build/test/install path and retain the installed API origin.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$repo/.build/home-validation}"
exec bash "$repo/Scripts/validate-planner-refresh.sh"
