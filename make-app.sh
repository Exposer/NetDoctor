#!/bin/bash
# Build a NetDoctor.app you can drop into /Applications (double-click to launch, no terminal window)
set -e; D="$(cd "$(dirname "$0")" && pwd)"; A="$D/NetDoctor.app/Contents"
rm -rf "$D/NetDoctor.app"; mkdir -p "$A/MacOS" "$A/Resources"
cp "$D/netdoctor" "$D/netdoctor-gui.py" "$A/Resources/"
cat > "$A/MacOS/NetDoctor" <<'X'
#!/bin/bash
DIR="$(cd "$(dirname "$0")/../Resources" && pwd)"
exec /usr/bin/env python3 "$DIR/netdoctor-gui.py"
X
cat > "$A/Info.plist" <<'X'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleName</key><string>NetDoctor</string><key>CFBundleExecutable</key><string>NetDoctor</string>
<key>CFBundleIdentifier</key><string>local.netdoctor</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1.0</string></dict></plist>
X
chmod +x "$A/MacOS/NetDoctor" "$A/Resources/netdoctor"
echo "Built $D/NetDoctor.app  (first launch: right-click → Open)"
