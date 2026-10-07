#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir/NativeTouchSendMethod.inc" <<'PY'
import pathlib, sys
source = pathlib.Path('VoidLink/Input/NativeTouchHandler.m').read_text(encoding='utf-8')
start = source.index('- (void)sendTouchEvent:')
end = source.index('\n- (void)touchesBegan:', start)
pathlib.Path(sys.argv[1]).write_text(source[start:end], encoding='utf-8')
PY
xcrun clang -fobjc-arc -framework Foundation -framework CoreGraphics \
  -I "$test_dir" -I moonlight-common/moonlight-common-c/src -I libs/opus/include/opus \
  Tests/NativeTouchPressureTests.m -o "$test_dir/native-touch-tests"
"$test_dir/native-touch-tests"
