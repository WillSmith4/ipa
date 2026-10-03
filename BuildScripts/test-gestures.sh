#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
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
xcrun momc VoidLink/Limelight.xcdatamodeld "$test_dir/Limelight.momd"
swiftc Tests/GestureSettingsMigrationTests.swift -import-objc-header VoidLink/Database/GestureSettingsMigration.h -parse-as-library -o "$test_dir/migration-tests"
"$test_dir/migration-tests" "$test_dir/Limelight.momd" "$test_dir"
