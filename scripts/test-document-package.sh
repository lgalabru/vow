#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_dir=$(mktemp -d)
trap 'rm -rf "$task_dir"' EXIT
xcrun swiftc "$repo_dir/apps/apple/Vow/VowDocument.swift" \
  "$repo_dir/apps/apple/DocumentPackageTests/main.swift" -o "$task_dir/document-tests"
"$task_dir/document-tests"
