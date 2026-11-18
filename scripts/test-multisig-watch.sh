#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc "$repo_dir/apps/apple/Vow/ObservedMultisigModels.swift" \
  "$repo_dir/apps/apple/MultisigWatchTests/main.swift" -o "$test_dir/watch-tests"
"$test_dir/watch-tests" "$repo_dir/apps/apple/Vow/Web/ObservedMultisigFixture.json"
