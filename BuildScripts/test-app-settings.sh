#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
python3 BuildScripts/prepare-profile-tests.py "$test_dir"
xcrun clang -fobjc-arc -fblocks -framework Foundation -I VoidLink/Database \
  VoidLink/Database/ApplicationProfileStore.m Tests/ApplicationProfileTests.m -o "$test_dir/assignment-tests"
"$test_dir/assignment-tests"
xcrun momc VoidLink/Limelight.xcdatamodeld "$test_dir/Limelight.momd"
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework CoreData -I "$test_dir" \
  Tests/SharedSessionSettingsTests.m -o "$test_dir/shared-settings-tests"
"$test_dir/shared-settings-tests" "$test_dir/Limelight.momd/VoidLink v1.8.mom"
xcrun clang -fobjc-arc -fblocks -c "$test_dir/OSCProfile.m" -o "$test_dir/OSCProfile.o"
xcrun clang -fobjc-arc -fblocks -c VoidLink/Database/ApplicationProfileStore.m -o "$test_dir/ApplicationProfileStore.o"
swiftc -I VoidLink/Database -import-objc-header "$test_dir/ProfileBridge.h" \
  "$test_dir/OSCProfilesManager.swift" "$test_dir/ProfileFileContainer.swift" "$test_dir/GameProfileTransfer.swift" \
  "$test_dir/OSCProfile.o" "$test_dir/ApplicationProfileStore.o" Tests/GameProfileTransferTests.swift \
  -framework AppKit -o "$test_dir/profile-transfer-tests"
"$test_dir/profile-transfer-tests" "$PWD/VoidLink/PresetConfigs/widgetTemplates.bin"
python3 Tests/check-session-profile-wiring.py
