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
<key>CFBundleShortVersionString</key><string>__VER__</string>
<key>CFBundleVersion</key><string>__VER__</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>NetDoctor scans and tests your local network to diagnose problems.</string>
</dict></plist>
X
# Keep the bundle version in sync with the CLI (netdoctor VERSION=...)
VER=$(sed -n 's/^VERSION=//p' ../netdoctor | head -1)
sed -i '' "s/__VER__/${VER:-1.0}/g" "$APP/Contents/Info.plist"
# Ad-hoc sign, then verify. A failure used to be swallowed silently. The usual cause is a folder synced by
# iCloud / File Provider (~/Documents, ~/Desktop): it keeps adding com.apple.FinderInfo, which codesign rejects.
xattr -cr "$APP" 2>/dev/null || true
if ! codesign --force --deep -s - "$APP" >/dev/null 2>&1 || ! codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  echo "warning: $APP has no valid code signature. This is usually caused by a synced folder (iCloud Drive," >&2
  echo "         ~/Documents, ~/Desktop). It still runs locally, but do not distribute it. To fix, build in a" >&2
  echo "         folder outside iCloud, or re-sign a copy:" >&2
  echo "           ditto --norsrc --noextattr $APP /tmp/$APP && xattr -cr /tmp/$APP && codesign --force --deep -s - /tmp/$APP" >&2
fi
echo "Built $(pwd)/$APP"
echo "Run: open $APP    Install: cp -R $APP /Applications/"
