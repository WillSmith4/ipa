#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir/SessionSettingsDataMethods.inc" <<'PY'
from pathlib import Path
import sys
source = Path('VoidLink/Database/DataManager.m').read_text(encoding='utf-8')
methods = []
for signature in ['- (Settings*) retrieveSettings {', '- (void) saveData {']:
    start = source.index(signature)
    end = source.index('\n- (', start + 1)
    methods.append(source[start:end])
Path(sys.argv[1]).write_text('\n'.join(methods), encoding='utf-8')
PY
xcrun momc VoidLink/Limelight.xcdatamodeld "$test_dir/Limelight.momd"
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework CoreData \
  -I VoidLink/Database -I "$test_dir" VoidLink/Database/ApplicationSettingsStore.m \
  Tests/ApplicationSettingsTests.m -o "$test_dir/app-settings-tests"
"$test_dir/app-settings-tests" "$test_dir/Limelight.momd/VoidLink v1.7.mom"
python3 - "$test_dir/ConnectionStopMethod.inc" <<'PY'
from pathlib import Path
import sys
source = Path('VoidLink/Stream/Connection.m').read_text(encoding='utf-8')
start = source.index('- (void)terminateWithCompletion:')
end = source.index('\n- (', start + 1)
Path(sys.argv[1]).write_text(source[start:end], encoding='utf-8')
PY
xcrun clang -fobjc-arc -fblocks -framework Foundation -I "$test_dir" \
  Tests/ConnectionStopTests.m -o "$test_dir/connection-stop-tests"
"$test_dir/connection-stop-tests"
