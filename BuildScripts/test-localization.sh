#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
app="$test_dir/LocalizationTests.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.voidlink.localization-tests</string>
<key>CFBundleExecutable</key><string>LocalizationTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST
xcrun xcstringstool compile --output-directory "$app/Contents/Resources" VoidLink/Localization/Localizable.xcstrings
xcrun clang -fobjc-arc -I VoidLink/Localization -c VoidLink/Localization/LocalizationHelper.m -o "$test_dir/localization.o"
xcrun clang -fobjc-arc -I VoidLink/Localization -c Tests/LocalizationTestBridge.m -o "$test_dir/bridge.o"
xcrun swiftc -I VoidLink/Localization -import-objc-header Tests/LocalizationTestBridge.h \
  VoidLink/Localization/LocalizationHelperExtension.swift Tests/LocalizationTests.swift \
  "$test_dir/localization.o" "$test_dir/bridge.o" -o "$app/Contents/MacOS/LocalizationTests"
for language in en pl zh-Hans zh-Hant zh-HK fr; do
  "$app/Contents/MacOS/LocalizationTests" -AppleLanguages "($language)"
done
# Reproduce the reported bug even after adding the Polish pairing translation:
# the preferred language exists but its PIN template is missing.
plutil -convert binary1 "$app/Contents/Resources/pl.lproj/Localizable.strings"
/usr/libexec/PlistBuddy -c 'Delete :Enter_PIN_Msg' "$app/Contents/Resources/pl.lproj/Localizable.strings"
"$app/Contents/MacOS/LocalizationTests" -AppleLanguages '(pl)'
