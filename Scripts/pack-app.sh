#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo 'edgelesstype requires an M-series Mac.' >&2; exit 1
fi
swift build -c release -Xswiftc "-file-prefix-map" -Xswiftc "$ROOT=/src/edgelesstype" -Xswiftc "-debug-prefix-map" -Xswiftc "$ROOT=/src/edgelesstype"
APP="$ROOT/edgelesstype.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/edgelesstype" "$APP/Contents/MacOS/edgelesstype"
cp "$ROOT/Config/app.example.json" "$APP/Contents/Resources/app.json"
cp "$ROOT/Resources/"*.wav "$APP/Contents/Resources/"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>edgelesstype</string>
  <key>CFBundleIdentifier</key>
  <string>edgelessblade.opentypeless</string>
  <key>CFBundleName</key>
  <string>edgelesstype</string>
  <key>CFBundleDisplayName</key>
  <string>edgelesstype</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>只有短按 Fn 之後才錄音。預設使用本機 Whisper；只有選用 OpenAI 雲端辨識時，錄音才會傳送至 OpenAI。處理後刪除本機暫存錄音。</string>
</dict>
</plist>
PLIST
chmod 755 "$APP/Contents/MacOS/edgelesstype"
strip -S "$APP/Contents/MacOS/edgelesstype"
codesign --force --sign "${SIGNING_IDENTITY:--}" --identifier edgelessblade.opentypeless "$APP"
echo "packed"
