#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -framework Foundation -I VoidLink/Database \
  VoidLink/Database/StatusBarPreferences.m VoidLink/Database/ApplicationSettingsStore.m \
  Tests/StatusBarPreferencesTests.m -o "$test_dir/status-bar-tests"
"$test_dir/status-bar-tests"
python3 - <<'PY'
from pathlib import Path
import plistlib
with Path('VoidLink/Limelight-Info.plist').open('rb') as f:
    info = plistlib.load(f)
assert info['UIViewControllerBasedStatusBarAppearance'] is True, 'UIKit must query the controller preference'
assert info['UIStatusBarHidden'] is True, 'Keep the launch default hidden'
print('Status bar: controller-based visibility and hidden launch default enabled')
PY
