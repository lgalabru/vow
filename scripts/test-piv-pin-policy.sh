#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc "$repo_dir/apps/apple/Vow/PIVPINPolicy.swift" \
  "$repo_dir/apps/apple/Vow/PIVSetupCoordinator.swift" \
  "$repo_dir/apps/apple/PolicyTests/main.swift" -o "$test_dir/pin-policy-tests"
"$test_dir/pin-policy-tests"
