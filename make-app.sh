#!/bin/bash
# 生成可放进“应用程序”的 NetDiag.app (双击启动, 无终端窗口)
set -e; D="$(cd "$(dirname "$0")" && pwd)"; A="$D/NetDiag.app/Contents"
rm -rf "$D/NetDiag.app"; mkdir -p "$A/MacOS" "$A/Resources"
cp "$D/netdiag" "$D/netdiag-gui.py" "$A/Resources/"
cat > "$A/MacOS/NetDiag" <<'X'
#!/bin/bash
DIR="$(cd "$(dirname "$0")/../Resources" && pwd)"
exec /usr/bin/env python3 "$DIR/netdiag-gui.py"
X
cat > "$A/Info.plist" <<'X'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleName</key><string>NetDiag</string><key>CFBundleExecutable</key><string>NetDiag</string>
<key>CFBundleIdentifier</key><string>local.netdiag</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1.0</string></dict></plist>
X
chmod +x "$A/MacOS/NetDiag" "$A/Resources/netdiag"
echo "已生成 $D/NetDiag.app  (首次打开: 右键 → 打开)"
