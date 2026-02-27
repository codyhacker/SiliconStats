#!/bin/bash
set -euo pipefail

APP_NAME="SiliconStats"
BUNDLE_ID="com.local.siliconstats"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "==> Building release binary..."
swift build -c release

echo "==> Creating app icon..."
ICONSET_DIR="AppIcon.iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"
sips -z 16 16     icon.png --out "${ICONSET_DIR}/icon_16x16.png"      > /dev/null
sips -z 32 32     icon.png --out "${ICONSET_DIR}/icon_16x16@2x.png"   > /dev/null
sips -z 32 32     icon.png --out "${ICONSET_DIR}/icon_32x32.png"      > /dev/null
sips -z 64 64     icon.png --out "${ICONSET_DIR}/icon_32x32@2x.png"   > /dev/null
sips -z 128 128   icon.png --out "${ICONSET_DIR}/icon_128x128.png"    > /dev/null
sips -z 256 256   icon.png --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   icon.png --out "${ICONSET_DIR}/icon_256x256.png"    > /dev/null
sips -z 512 512   icon.png --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   icon.png --out "${ICONSET_DIR}/icon_512x512.png"    > /dev/null
sips -z 1024 1024 icon.png --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null
iconutil -c icns "${ICONSET_DIR}" -o AppIcon.icns
rm -rf "${ICONSET_DIR}"

echo "==> Assembling ${APP_BUNDLE}..."
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>SiliconStats</string>
    <key>CFBundleDisplayName</key>
    <string>SiliconStats</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Code signing (ad-hoc)..."
codesign --force --sign - "${APP_BUNDLE}"

echo "==> Installing to /Applications..."
if [ -d "/Applications/${APP_BUNDLE}" ]; then
    echo "    Removing existing installation..."
    rm -rf "/Applications/${APP_BUNDLE}"
fi
cp -R "${APP_BUNDLE}" "/Applications/${APP_BUNDLE}"

echo ""
echo "Done! SiliconStats is installed at /Applications/${APP_BUNDLE}"
echo "You can launch it from Spotlight by searching \"SiliconStats\"."
