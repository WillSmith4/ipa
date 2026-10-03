#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc VoidLink/Input/GestureActionEngine.swift Tests/GestureActionEngineTests.swift -o "$test_dir/gesture-tests"
"$test_dir/gesture-tests"
xcrun momc VoidLink/Limelight.xcdatamodeld "$test_dir/Limelight.momd"
swiftc Tests/GestureSettingsMigrationTests.swift -import-objc-header VoidLink/Database/GestureSettingsMigration.h -parse-as-library -o "$test_dir/migration-tests"
"$test_dir/migration-tests" "$test_dir/Limelight.momd" "$test_dir"
