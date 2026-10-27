#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
python3 BuildScripts/test-ordered-mouse.py
python3 - "$test_dir/StreamSwipeRecognizer.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('VoidLink/Input/StreamGestureController.swift').read_text(encoding='utf-8')
start = source.index('private final class StreamSwipeRecognizer:')
end = source.index('/// Camera gestures', start)
pathlib.Path(sys.argv[1]).write_text('import Foundation\nimport CoreGraphics\n' + source[start:end].replace('private final class', 'final class', 1), encoding='utf-8')
start = source.index('    private func updateEnabled() {')
end = source.index('\n    @objc func cancel()', start)
with pathlib.Path(sys.argv[1]).open('a', encoding='utf-8') as output:
    output.write('''
final class GestureRoutingHarness {
    var enabled = true, singlePointMode = false
    var actions = ["SCROLL_DOWN", "SCROLL_UP", "MOUSE_MIDDLE", "MOUSE_LEFT"]
    let cursorEnabled = [false, false, true, true]
    let pinch = UIGestureRecognizer(), rotation = UIGestureRecognizer()
    let swipe = UIGestureRecognizer(), motionObserver = UIGestureRecognizer()
    let twoFingerTap = UIGestureRecognizer()
    var twoFingerTapAction = (enabled: true, unused: false)
''')
    output.write(source[start:end].replace('private func', 'func', 1) + '\n}\n')
PY
swiftc "$test_dir/StreamSwipeRecognizer.swift" Tests/SwipeStartTests.swift -o "$test_dir/swipe-start-tests"
"$test_dir/swipe-start-tests"
# Compile the actual key map without CommandManager's UIKit dependencies.
python3 - "$test_dir/GestureTestKeyboard.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('VoidLink/Input/CommandManager.swift').read_text(encoding='utf-8')
start = source.index('@objc public static let keyboardButtonMappings:')
end = source.index('\n    ]', start) + len('\n    ]')
declaration = source[start:end].replace('@objc public ', '', 1)
pathlib.Path(sys.argv[1]).write_text('enum GestureTestKeyboard {\n' + declaration + '\n}\n', encoding='utf-8')
PY
swiftc VoidLink/Input/GestureActionEngine.swift "$test_dir/GestureTestKeyboard.swift" Tests/GestureActionEngineTests.swift -o "$test_dir/gesture-tests"
"$test_dir/gesture-tests"
python3 - "$test_dir/GestureLongPressAction.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('VoidLink/Input/StreamGestureController.swift').read_text(encoding='utf-8')
start = source.index('@objc final class GestureLongPressAction:')
end = source.index('/// Shared editor', start)
pathlib.Path(sys.argv[1]).write_text('import Foundation\nimport QuartzCore\n' + source[start:end], encoding='utf-8')
PY
swiftc VoidLink/Input/GestureActionEngine.swift "$test_dir/GestureTestKeyboard.swift" \
  "$test_dir/GestureLongPressAction.swift" Tests/LongPressActionTests.swift -o "$test_dir/long-press-tests"
"$test_dir/long-press-tests"
python3 - "$test_dir/TouchPadGestureHandler.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('VoidLink/Input/TouchPadGestureHandler.swift').read_text(encoding='utf-8')
pathlib.Path(sys.argv[1]).write_text(source.replace('import UIKit', 'import Foundation\nimport CoreGraphics'), encoding='utf-8')
PY
swiftc "$test_dir/TouchPadGestureHandler.swift" Tests/TouchpadGestureTests.swift -o "$test_dir/touchpad-tests"
"$test_dir/touchpad-tests"
python3 - "$test_dir/TouchpadRightClickMethods.inc" <<'PY'
import pathlib, sys
source = pathlib.Path('VoidLink/Input/RelativeTouchHandler.m').read_text(encoding='utf-8')
methods = []
for name in ['mouseRightClick', 'touchesCancelled:', 'sendLongMouseLeftButtonClickEvent']:
    start = source.index('- (void)' + name)
    end = source.index('\n- (', start + 1)
    methods.append(source[start:end])
pathlib.Path(sys.argv[1]).write_text('\n'.join(methods), encoding='utf-8')
PY
xcrun clang -fobjc-arc -fblocks -framework Foundation -I "$test_dir" \
  Tests/TouchpadRightClickTests.m -o "$test_dir/touchpad-right-click-tests"
"$test_dir/touchpad-right-click-tests"
python3 - "$test_dir/AbsoluteDragHandoffMethods.inc" <<'PY'
import pathlib, sys
source = pathlib.Path('VoidLink/Input/AbsoluteTouchHandler.m').read_text(encoding='utf-8')
methods = []
for name in ['beginDoubleTapDrag', 'sendShortMouseLeftButtonClickEvent']:
    start = source.index('- (void)' + name)
    end = source.index('\n- (', start + 1)
    methods.append(source[start:end])
pathlib.Path(sys.argv[1]).write_text('\n'.join(methods), encoding='utf-8')
PY
xcrun clang -fobjc-arc -fblocks -framework Foundation -I "$test_dir" \
  Tests/AbsoluteDragHandoffTests.m -o "$test_dir/absolute-drag-tests"
"$test_dir/absolute-drag-tests"
xcrun momc VoidLink/Limelight.xcdatamodeld "$test_dir/Limelight.momd"
swiftc Tests/GestureSettingsMigrationTests.swift -import-objc-header VoidLink/Database/GestureSettingsMigration.h -parse-as-library -o "$test_dir/migration-tests"
"$test_dir/migration-tests" "$test_dir/Limelight.momd" "$test_dir"
