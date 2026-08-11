#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"

cd "${repository_root}"
swift package plugin \
    --allow-writing-to-package-directory \
    generate-code-from-openapi \
    --target RepbaseAPI
