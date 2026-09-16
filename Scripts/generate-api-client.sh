#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"
derived_contract="${repository_root}/.build/repbase-openapi-ios.yaml"

cd "${repository_root}"
mkdir -p "${repository_root}/.build"
ruby "${script_directory}/prepare-ios-openapi.rb" \
    "${repository_root}/API/openapi.yaml" \
    "${derived_contract}"

# A scratch path of its own, so CI can cache the compiled generator without
# also caching Xcode.s DerivedData, which lives under .build and is large,
# machine-specific and worthless between runs. Building the generator from
# source was a minute of every run.
swift run --scratch-path "${repository_root}/.swiftpm-build" swift-openapi-generator generate \
    "${derived_contract}" \
    --config "${repository_root}/API/openapi-generator-config.yaml" \
    --output-directory "${repository_root}/API/GeneratedSources"
