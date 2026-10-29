#!/bin/sh
# Build the hpcups Status menu bar app and wrap it into build/hpcups Status.app.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="hpcups Status"
BUNDLE_ID="io.github.gamunu.hpcups-status"
VERSION="${VERSION:-0.1.0}"
OUT="$ROOT/build/$APP_NAME.app"

cd "$ROOT/app"
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN_DIR/HPCupsStatus" "$OUT/Contents/MacOS/$APP_NAME"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force -s - "$OUT"
echo "Built $OUT"
