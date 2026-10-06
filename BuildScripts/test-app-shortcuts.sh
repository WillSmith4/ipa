#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
MACOSX_DEPLOYMENT_TARGET=14.0 swiftc VoidLink/ApplicationShortcutModels.swift \
  VoidLink/WebClipProfileServer.swift Tests/ApplicationShortcutTests.swift \
  -parse-as-library -o "$test_dir/app-shortcut-tests"
"$test_dir/app-shortcut-tests"
