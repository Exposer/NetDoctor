#!/bin/bash
# Build NetDoctor.app (only needs the Xcode command line tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"
ARCHS=""; [ "${UNIVERSAL:-}" = 1 ] && ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/NetDoctor"

APP="NetDoctor.app"; rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NetDoctor"
cp ../netdoctor "$APP/Contents/Resources/netdoctor"; chmod +x "$APP/Contents/Resources/netdoctor"
cp ../assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Localizations (English + Simplified Chinese); the app follows the system language
for d in Resources/*.lproj; do
  plutil -lint "$d/Localizable.strings" >/dev/null
  cp -R "$d" "$APP/Contents/Resources/"
done
cat > "$APP/Contents/Info.plist" <<'X'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>NetDoctor</string>
<key>CFBundleDisplayName</key><string>NetDoctor</string>
<key>CFBundleExecutable</key><string>NetDoctor</string>
<key>CFBundleIdentifier</key><string>local.netdoctor.app</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.7</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
X
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
echo "Built $(pwd)/$APP"
echo "Run: open $APP    Install: cp -R $APP /Applications/"
