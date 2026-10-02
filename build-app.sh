#!/bin/zsh
# Builds a release Shelf.app with the Icon Composer icon compiled in.
set -euo pipefail
cd "${0:A:h}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Shelf"

APP="build/Shelf.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shelf"

xcrun actool Icon.icon --compile "$APP/Contents/Resources" \
    --output-format human-readable-text --notices --warnings --errors \
    --output-partial-info-plist build/icon-partial.plist \
    --app-icon Icon --include-all-app-icons \
    --target-device mac --platform macosx --minimum-deployment-target 14.0

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Shelf</string>
    <key>CFBundleIdentifier</key><string>com.shelf.app</string>
    <key>CFBundleName</key><string>Shelf</string>
    <key>CFBundleDisplayName</key><string>Shelf</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>CFBundleIconName</key><string>Icon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP"
echo "Built $APP"
