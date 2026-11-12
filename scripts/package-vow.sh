#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_dir=$(mktemp -d)
trap 'rm -rf "$task_dir"' EXIT
xcrun swiftc "$repo_dir/apps/apple/Vow/VowDocument.swift" \
  "$repo_dir/apps/apple/DocumentPackageTool/main.swift" -o "$task_dir/package-vow"
"$task_dir/package-vow" "$@"
