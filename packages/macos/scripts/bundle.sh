#!/bin/bash
# Build Ocean and wrap it in a .app bundle.
#
# SwiftPM cannot emit an application bundle, and this machine has Command Line
# Tools rather than Xcode, so there is no xcodebuild to do it either. The bundle
# is therefore assembled by hand: it is only a directory with a binary and an
# Info.plist, and doing it here keeps the build reproducible without Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Ocean.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Ocean"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ocean"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Ocean</string>
  <key>CFBundleDisplayName</key><string>Ocean</string>
  <key>CFBundleIdentifier</key><string>in.4nkitd.ocean</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Ocean</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Ocean uses the microphone to dictate prompts.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Ocean transcribes dictated prompts into the composer.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
</dict>
</plist>
PLIST

# Ad-hoc signature: unsigned bundles are killed on launch on Apple silicon.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "$APP"
