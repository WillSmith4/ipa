#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc VoidLink/Input/GestureActionEngine.swift Tests/GestureActionEngineTests.swift -o "$test_dir/gesture-tests"
"$test_dir/gesture-tests"
