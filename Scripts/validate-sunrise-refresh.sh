#!/usr/bin/env bash
# Build all five Sunrise pages through the established test/install path.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$repo/.build/sunrise-validation}"
exec bash "$repo/Scripts/validate-planner-refresh.sh"
