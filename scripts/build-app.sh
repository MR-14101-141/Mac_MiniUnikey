#!/usr/bin/env bash
#
# Build MiniUnikey.app (menu-bar app) từ SPM release build.
# Chạy: ./scripts/build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MiniUnikey"
BUNDLE_ID="vn.miniunikey.app"

cd "$ROOT"

if ! command -v swift >/dev/null 2>&1; then
  echo "❌ Cần Xcode Command Line Tools (xcode-select --install)"
  exit 1
fi

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
APP="$BIN_DIR/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

if [ -f "$ROOT/assets/MiniUnikey.icns" ]; then
  cp "$ROOT/assets/MiniUnikey.icns" "$APP/Contents/Resources/MiniUnikey.icns"
fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MiniUnikey</string>
    <key>CFBundleDisplayName</key><string>MiniUnikey</string>
    <key>CFBundleIdentifier</key><string>vn.miniunikey.app</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>MiniUnikey</string>
    <key>CFBundleIconFile</key><string>MiniUnikey</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Bộ gõ tiếng Việt kiểu VNI. Thuật toán lấy từ engine UniKey (LGPL).</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
EOF

echo 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP"

echo ""
echo "✅ Đã tạo: $APP"
echo "   Mở thử:  open \"$APP\""
