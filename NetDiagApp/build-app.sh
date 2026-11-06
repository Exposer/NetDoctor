#!/bin/bash
# 构建 NetDiag.app (只需 Xcode 命令行工具: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"
ARCHS=""; [ "${UNIVERSAL:-}" = 1 ] && ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/NetDiag"

APP="NetDiag.app"; rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NetDiag"
cp ../netdiag "$APP/Contents/Resources/netdiag"; chmod +x "$APP/Contents/Resources/netdiag"
cat > "$APP/Contents/Info.plist" <<'X'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>NetDiag</string>
<key>CFBundleDisplayName</key><string>NetDiag</string>
<key>CFBundleExecutable</key><string>NetDiag</string>
<key>CFBundleIdentifier</key><string>local.netdiag.app</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
X
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
echo "已生成 $(pwd)/$APP"
echo "运行: open $APP    安装: cp -R $APP /Applications/"
